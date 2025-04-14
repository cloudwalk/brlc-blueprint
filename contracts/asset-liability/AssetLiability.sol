// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { AccessControlExtUpgradeable } from "../base/AccessControlExtUpgradeable.sol";
import { PausableExtUpgradeable } from "../base/PausableExtUpgradeable.sol";
import { RescuableUpgradeable } from "../base/RescuableUpgradeable.sol";
import { UUPSExtUpgradeable } from "../base/UUPSExtUpgradeable.sol";
import { Versionable } from "../base/Versionable.sol";

import { AssetLiabilityStorage } from "./AssetLiabilityStorage.sol";

import { IAssetLiability } from "./IAssetLiability.sol";
import { IAssetLiabilityPrimary } from "./IAssetLiability.sol";
import { IAssetLiabilityConfiguration } from "./IAssetLiability.sol";
import { IAssetLiabilityTypes } from "./IAssetLiabilityTypes.sol";

/**
 * @title AssetLiability contract
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev The contract that manages the asset liability of accounts.
 */
contract AssetLiability is
    AssetLiabilityStorage,
    AccessControlExtUpgradeable,
    PausableExtUpgradeable,
    RescuableUpgradeable,
    UUPSExtUpgradeable,
    Versionable,
    IAssetLiability
{
    // ------------------ Constants ------------------------------- //

    /// @dev The role of this contract owner.
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    /// @dev The role of operator that is allowed to perform operations with the liability.
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ------------------ Constructor ----------------------------- //

    /// @dev Constructor that prohibits the initialization of the implementation of the upgradable contract.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ------------------ Initializers ---------------------------- //

    /**
     * @dev Initializer of the upgradable contract.
     *
     * See details: https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable
     *
     * @param token_ The address of the token to set as the underlying one.
     */
    function initialize(address token_) external initializer {
        __AccessControlExt_init_unchained(); // This is needed only to avoid errors during coverage assessment
        __PausableExt_init_unchained(OWNER_ROLE);
        __Rescuable_init_unchained(OWNER_ROLE);
        __UUPSExt_init_unchained(); // This is needed only to avoid errors during coverage assessment
        __AssetLiability_init_unchained(token_);
    }

    function __AssetLiability_init_unchained(address token_) internal {
        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, OWNER_ROLE);
        _grantRole(OWNER_ROLE, _msgSender());

        if (token_ == address(0)) {
            revert AssetLiability_UnderlyingTokenAddressZero();
        }

        _token = token_;
    }

    // ------------------ Transactional functions ----------------- //

    /**
     * @inheritdoc IAssetLiabilityPrimary
     *
     * @dev Requirements:
     *
     * - The caller must have the {OPERATOR_ROLE} role.
     * - The length of accounts and amounts arrays must match.
     *
     * Emits multiple {LiabilityUpdated} events.
     */
    function transferWithLiability(
        address[] calldata accounts,
        uint256[] calldata amounts
    ) external onlyRole(OPERATOR_ROLE) {
        if (accounts.length != amounts.length) {
            revert AssetLiability_AccountsAndAmountsLengthMismatch();
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            _transferWithLiability(accounts[i], amounts[i]);
        }
    }

    /**
     * @inheritdoc IAssetLiabilityPrimary
     *
     * @dev Requirements:
     *
     * - The caller must have the {OPERATOR_ROLE} role.
     * - The length of accounts and amounts arrays must match.
     *
     * Emits multiple {LiabilityUpdated} events.
     */
    function increaseLiability(
        address[] calldata accounts,
        uint256[] calldata amounts
    ) external onlyRole(OPERATOR_ROLE) {
        if (accounts.length != amounts.length) {
            revert AssetLiability_AccountsAndAmountsLengthMismatch();
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            _increaseLiability(accounts[i], amounts[i]);
        }
    }

    /**
     * @inheritdoc IAssetLiabilityPrimary
     *
     * @dev Requirements:
     *
     * - The caller must have the {OPERATOR_ROLE} role.
     * - The length of accounts and amounts arrays must match.
     *
     * Emits multiple {LiabilityUpdated} events.
     */
    function reduceLiability(address[] calldata accounts, uint256[] calldata amounts) external onlyRole(OPERATOR_ROLE) {
        //
        if (accounts.length != amounts.length) {
            revert AssetLiability_AccountsAndAmountsLengthMismatch();
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            _reduceLiability(accounts[i], amounts[i]);
        }
    }

    // ------------------ View functions -------------------------- //

    /**
     * @inheritdoc IAssetLiabilityPrimary
     */
    function liabilityOf(address account) external view returns (uint256) {
        return _liabilities[account].amount;
    }

    /**
     * @inheritdoc IAssetLiabilityPrimary
     */
    function totalLiability() external view returns (uint256) {
        return _totalLiability;
    }

    // ------------------ Pure functions -------------------------- //

    /// @inheritdoc IAssetLiability
    function proveAssetLiability() external pure {}

    // ------------------ Configuration functions ----------------- //

    /**
     * @inheritdoc IAssetLiabilityConfiguration
     *
     * @dev Requirements:
     *
     * - The caller must have the {OWNER_ROLE} role.
     * - The new treasury address must not be the same as currently set.
     *
     * Emits a {TreasuryUpdated} event.
     */
    function setOperationalTreasury(address treasury_) external onlyRole(OWNER_ROLE) {
        if (treasury_ == _treasury) {
            revert AssetLiability_TreasuryAddressAlreadySet();
        }

        emit TreasuryUpdated(treasury_, _treasury);

        _treasury = treasury_;
    }

    /**
     * @inheritdoc IAssetLiabilityConfiguration
     */
    function underlyingToken() external view returns (address) {
        return _token;
    }

    /**
     * @inheritdoc IAssetLiabilityConfiguration
     */
    function operationalTreasury() external view returns (address) {
        return _treasury;
    }

    // ------------------ Internal functions ---------------------- //

    /**
     * @dev Transfers tokens to an account and increases its liability.
     *
     * @param account The account to transfer tokens to.
     * @param amount The amount of tokens to transfer.
     */
    function _transferWithLiability(address account, uint256 amount) internal {
        _increaseLiability(account, amount);
        SafeERC20.safeTransferFrom(IERC20(_token), _treasury, account, amount);
    }

    /**
     * @dev Increases the liability of an account.
     *
     * @param account The account to increase the liability for.
     * @param amount The amount to increase the liability by.
     *
     * Emits a {LiabilityUpdated} event.
     */
    function _increaseLiability(address account, uint256 amount) internal {
        if (account == address(0)) {
            revert AssetLiability_AccountAddressZero();
        }

        if (amount == 0) {
            revert AssetLiability_AmountZero();
        }

        Liability storage liability = _liabilities[account];
        uint256 oldLiability = liability.amount;

        liability.amount += uint64(amount);
        _totalLiability += amount;

        emit LiabilityUpdated(account, liability.amount, oldLiability);
    }

    /**
     * @dev Reduces the liability of an account.
     *
     * @param account The account to reduce the liability for.
     * @param amount The amount to reduce the liability by.
     *
     * Emits a {LiabilityUpdated} event.
     */
    function _reduceLiability(address account, uint256 amount) internal {
        if (account == address(0)) {
            revert AssetLiability_AccountAddressZero();
        }

        if (amount == 0) {
            revert AssetLiability_AmountZero();
        }

        Liability storage liability = _liabilities[account];
        uint256 oldLiability = liability.amount;

        if (amount > oldLiability) {
            revert AssetLiability_ReductionAmountExcess();
        }

        unchecked {
            liability.amount -= uint64(amount);
            _totalLiability -= amount;
        }

        emit LiabilityUpdated(account, liability.amount, oldLiability);
    }

    /**
     * @dev The upgrade validation function for the UUPSExtUpgradeable contract.
     *
     * @param newImplementation The address of the new implementation.
     */
    function _validateUpgrade(address newImplementation) internal view override onlyRole(OWNER_ROLE) {
        try IAssetLiability(newImplementation).proveAssetLiability() {} catch {
            revert AssetLiability_ImplementationAddressInvalid();
        }
    }
}
