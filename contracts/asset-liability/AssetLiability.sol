// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

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

/**
 * @title AssetLiability contract
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev The contract that manages the asset liability of accounts.
 * @custom:storage-layout Uses ERC-7201 namespaced storage pattern.
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

    /// @dev The role of manager that is allowed to perform operations with the liability.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

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
     * Requirements:
     *
     * - The function must not be called more than once.
     * - The token address must not be zero.
     *
     * @param underlyingToken_ The address of the token to set as the underlying one.
     * This is the ERC20 token that will be used for transfers and liability tracking.
     * Cannot be zero address.
     */
    function initialize(address underlyingToken_) external initializer {
        __AccessControlExt_init(); // This is needed only to avoid errors during coverage assessment
        __PausableExt_init(OWNER_ROLE);
        __Rescuable_init(OWNER_ROLE);
        __UUPSExt_init(); // This is needed only to avoid errors during coverage assessment
        __AssetLiability_init_unchained(underlyingToken_);
    }

    /**
     * @dev Unchained version of the initializer.
     *
     * Requirements:
     *
     * - The token address must not be zero.
     *
     * @param underlyingToken_ The address of the token to set as the underlying one.
     */
    function __AssetLiability_init_unchained(address underlyingToken_) internal {
        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
        _setRoleAdmin(MANAGER_ROLE, OWNER_ROLE);
        _grantRole(OWNER_ROLE, _msgSender());

        if (underlyingToken_ == address(0)) {
            revert AssetLiability_UnderlyingTokenAddressZero();
        }

        _getAssetLiabilityStorage().underlyingToken = underlyingToken_;
    }

    // ------------------ Configuration functions ----------------- //

    /**
     * @inheritdoc IAssetLiabilityConfiguration
     *
     * @dev Requirements:
     *
     * - The caller must have the {OWNER_ROLE} role.
     * - The new treasury address must not be the same as currently set.
     */
    function setOperationalTreasury(address operationalTreasury_) external onlyRole(OWNER_ROLE) {
        AssetLiabilityData storage data = _getAssetLiabilityStorage();

        if (operationalTreasury_ == data.operationalTreasury) {
            revert AssetLiability_TreasuryAddressAlreadySet();
        }

        emit TreasuryUpdated(operationalTreasury_, data.operationalTreasury);

        data.operationalTreasury = operationalTreasury_;
    }

    /**
     * @inheritdoc IAssetLiabilityConfiguration
     */
    function underlyingToken() external view returns (address) {
        return _getAssetLiabilityStorage().underlyingToken;
    }

    /**
     * @inheritdoc IAssetLiabilityConfiguration
     */
    function operationalTreasury() external view returns (address) {
        return _getAssetLiabilityStorage().operationalTreasury;
    }

    // ------------------ Transactional functions ----------------- //

    /**
     * @inheritdoc IAssetLiabilityPrimary
     *
     * @dev Requirements:
     *
     * - The contract must not be paused.
     * - The caller must have the {MANAGER_ROLE} role.
     * - The length of accounts and amounts arrays must match.
     * - None of the account addresses can be zero.
     * - None of the amounts can be zero.
     * - None of the amounts can exceed the maximum uint64 value.
     */
    function transferWithLiability(
        address[] calldata accounts,
        uint256[] calldata amounts
    ) external whenNotPaused onlyRole(MANAGER_ROLE) {
        uint256 length = accounts.length;

        if (length != amounts.length) {
            revert AssetLiability_AccountsAndAmountsLengthMismatch();
        }

        for (uint256 i = 0; i < length; ) {
            _transferWithLiability(accounts[i], amounts[i]);
            unchecked {
                ++i;
            } // Gas optimization - no risk of overflow with reasonable array sizes
        }
    }

    /**
     * @inheritdoc IAssetLiabilityPrimary
     *
     * @dev Requirements:
     *
     * - The contract must not be paused.
     * - The caller must have the {MANAGER_ROLE} role.
     * - The length of accounts and amounts arrays must match.
     * - None of the account addresses can be zero.
     * - None of the amounts can be zero.
     * - None of the amounts can exceed the maximum uint64 value.
     */
    function increaseLiability(
        address[] calldata accounts,
        uint256[] calldata amounts
    ) external whenNotPaused onlyRole(MANAGER_ROLE) {
        uint256 length = accounts.length;

        if (length != amounts.length) {
            revert AssetLiability_AccountsAndAmountsLengthMismatch();
        }

        for (uint256 i = 0; i < length; ) {
            _increaseLiability(accounts[i], amounts[i]);
            unchecked {
                ++i;
            } // Gas optimization - no risk of overflow with reasonable array sizes
        }
    }

    /**
     * @inheritdoc IAssetLiabilityPrimary
     *
     * @dev Requirements:
     *
     * - The contract must not be paused.
     * - The caller must have the {MANAGER_ROLE} role.
     * - The length of accounts and amounts arrays must match.
     * - None of the account addresses can be zero.
     * - None of the amounts can be zero.
     * - None of the amounts can exceed the maximum uint64 value.
     * - None of the amounts can exceed the current liability of the respective account.
     */
    function decreaseLiability(
        address[] calldata accounts,
        uint256[] calldata amounts
    ) external whenNotPaused onlyRole(MANAGER_ROLE) {
        uint256 length = accounts.length;

        if (length != amounts.length) {
            revert AssetLiability_AccountsAndAmountsLengthMismatch();
        }

        for (uint256 i = 0; i < length; ) {
            _decreaseLiability(accounts[i], amounts[i]);
            unchecked {
                ++i;
            } // Gas optimization - no risk of overflow with reasonable array sizes
        }
    }

    // ------------------ View functions -------------------------- //

    /**
     * @inheritdoc IAssetLiabilityPrimary
     */
    function liabilityOf(address account) external view returns (uint256) {
        return _getAssetLiabilityStorage().liabilities[account].amount;
    }

    /**
     * @inheritdoc IAssetLiabilityPrimary
     */
    function totalLiability() external view returns (uint256) {
        return _getAssetLiabilityStorage().totalLiability;
    }

    // ------------------ Pure functions -------------------------- //

    /// @inheritdoc IAssetLiability
    function proveAssetLiability() external pure {}

    // ------------------ Internal functions ---------------------- //

    /**
     * @dev Transfers tokens to an account and increases its liability.
     *
     * Requirements:
     *
     * - The account address must not be zero.
     * - The amount must not be zero.
     * - The amount must not exceed the maximum uint64 value.
     * - The treasury must have sufficient tokens and allowance.
     *
     * @param account The account to transfer tokens to.
     * @param amount The amount of tokens to transfer.
     *
     * Emits a {LiabilityUpdated} event (via the _increaseLiability function).
     */
    function _transferWithLiability(address account, uint256 amount) internal {
        _increaseLiability(account, amount);
        AssetLiabilityData storage data = _getAssetLiabilityStorage();
        SafeERC20.safeTransferFrom(IERC20(data.underlyingToken), data.operationalTreasury, account, amount);
    }

    /**
     * @dev Increases the liability of an account.
     *
     * Requirements:
     *
     * - The account address must not be zero.
     * - The amount must not be zero.
     * - The amount must not exceed the maximum uint64 value.
     *
     * @param account The account to increase the liability for.
     * @param amount The amount to increase the liability by.
     *
     * Emits a {LiabilityUpdated} event.
     */
    function _increaseLiability(address account, uint256 amount) internal {
        _checkLiabilityOperationParameters(account, amount);

        AssetLiabilityData storage data = _getAssetLiabilityStorage();
        Liability storage liability = data.liabilities[account];
        uint256 oldLiability = liability.amount;

        data.totalLiability += amount;
        uint256 newLiability = uint64(oldLiability) + uint64(amount); // Panic if result is larger than 64 bits
        liability.amount = uint64(newLiability);

        emit LiabilityUpdated(account, newLiability, oldLiability);
    }

    /**
     * @dev Decreases the liability of an account.
     *
     * Requirements:
     *
     * - The account address must not be zero.
     * - The amount must not be zero.
     * - The amount must not exceed the maximum uint64 value.
     * - The amount must not exceed the current liability of the account.
     *
     * @param account The account to decrease the liability for.
     * @param amount The amount to decrease the liability by.
     *
     * Emits a {LiabilityUpdated} event.
     */
    function _decreaseLiability(address account, uint256 amount) internal {
        _checkLiabilityOperationParameters(account, amount);

        AssetLiabilityData storage data = _getAssetLiabilityStorage();
        Liability storage liability = data.liabilities[account];
        uint256 oldLiability = liability.amount;

        if (amount > oldLiability) {
            revert AssetLiability_DecreaseAmountExcess();
        }

        // Safe to use unchecked here because:
        // 1. We've verified that amount <= oldLiability above
        // 2. data.totalLiability >= liability.amount by definition
        uint256 newLiability;
        unchecked {
            data.totalLiability -= amount;
            newLiability = oldLiability - amount;
            liability.amount = uint64(newLiability);
        }

        emit LiabilityUpdated(account, newLiability, oldLiability);
    }

    /**
     * @dev Checks the parameters of the liability operation.
     * @param account The account to decrease the liability for.
     * @param amount The amount to decrease the liability by.
     */
    function _checkLiabilityOperationParameters(address account, uint256 amount) internal pure {
        if (account == address(0)) {
            revert AssetLiability_AccountAddressZero();
        }

        if (amount == 0) {
            revert AssetLiability_AmountZero();
        }

        if (amount > type(uint64).max) {
            revert AssetLiability_AmountOverflow();
        }
    }

    /**
     * @dev The upgrade validation function for the UUPSExtUpgradeable contract.
     *
     * Requirements:
     *
     * - The caller must have the {OWNER_ROLE} role.
     * - The new implementation address must be a valid AssetLiability contract.
     *
     * @param newImplementation The address of the new implementation.
     */
    function _validateUpgrade(address newImplementation) internal view override onlyRole(OWNER_ROLE) {
        try IAssetLiability(newImplementation).proveAssetLiability() {} catch {
            revert AssetLiability_ImplementationAddressInvalid();
        }
    }
}
