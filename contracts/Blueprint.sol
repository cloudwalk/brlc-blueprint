// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AccessControlExtUpgradeable } from "./base/AccessControlExtUpgradeable.sol";
import { PausableExtUpgradeable } from "./base/PausableExtUpgradeable.sol";
import { RescuableUpgradeable } from "./base/RescuableUpgradeable.sol";
import { Versionable } from "./base/Versionable.sol";
import { UUPSExtUpgradeable } from "./base/UUPSExtUpgradeable.sol";

import { IBlueprint } from "./interfaces/IBlueprint.sol";
import { IBlueprintPrimary } from "./interfaces/IBlueprint.sol";
import { IBlueprintConfiguration } from "./interfaces/IBlueprint.sol";

import { BlueprintStorage } from "./BlueprintStorage.sol";

/**
 * @title Blueprint contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev The contract that responsible for freezing operations on the underlying token contract.
 *
 * See details about the contract in the comments of the {IBlueprint} interface.
 */
contract Blueprint is
    BlueprintStorage,
    AccessControlExtUpgradeable,
    PausableExtUpgradeable,
    RescuableUpgradeable,
    UUPSExtUpgradeable,
    Versionable,
    IBlueprint
{
    // ------------------ Constants ------------------------------- //

    /// @dev The role of this contract owner.
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    /// @dev The role of manager that is allowed to deposit and withdraw tokens to the contract.
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @dev The kind of operation that is deposit.
    uint256 internal constant OPERATION_KIND_DEPOSIT = 0;

    /// @dev The kind of operation that is withdrawal.
    uint256 internal constant OPERATION_KIND_WITHDRAWAL = 1;

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
     * See details https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable.
     *
     * @param token_ The address of the token to set as the underlying one.
     */
    function initialize(address token_) external initializer {
        __AccessControlExt_init();
        __PausableExt_init(OWNER_ROLE);
        __Rescuable_init(OWNER_ROLE);
        __UUPSUpgradeable_init();

        if (token_ == address(0)) {
            revert Blueprint_TokenAddressZero();
        }

        _token = token_;

        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
        _setRoleAdmin(MANAGER_ROLE, OWNER_ROLE);
        _grantRole(OWNER_ROLE, _msgSender());
    }

    // ------------------ Transactional functions ----------------- //

    /**
     * @inheritdoc IBlueprintConfiguration
     *
     * @dev Requirements:
     *
     * - The caller must have the {MANAGER_ROLE} role.
     * - The new operational treasury address must not be zero.
     * - The new operational treasury address must not be the same as already configured.
     */
    function setOperationalTreasury(address newTreasury) external onlyRole(MANAGER_ROLE) {
        if (newTreasury == address(0)) {
            revert Blueprint_TreasuryAddressZero();
        }
        address oldTreasury = _operationalTreasury;
        if (newTreasury == oldTreasury) {
            revert Blueprint_TreasuryAddressAlreadyConfigured();
        }

        emit OperationalTreasuryChanged(newTreasury, oldTreasury);
        _operationalTreasury = newTreasury;
    }

    /**
     * @inheritdoc IBlueprintPrimary
     *
     * @dev Requirements:
     *
     * - The contract must not be paused.
     * - The caller must have the {MANAGER_ROLE} role.
     * - The provided account address must not be zero.
     * - The provided operation identifier must not be zero.
     */
    function deposit(
        address account, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 amount,
        bytes32 opId
    ) external whenNotPaused onlyRole(MANAGER_ROLE) {
        _executeOperation(account, amount, opId, OPERATION_KIND_DEPOSIT);
    }

    /**
     * @inheritdoc IBlueprintPrimary
     *
     * @dev Requirements:
     *
     * - The contract must not be paused.
     * - The caller must have the {MANAGER_ROLE} role.
     * - The provided account address must not be zero.
     * - The provided operation identifier must not be zero.
     */
    function withdraw(
        address account, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 amount,
        bytes32 opId
    ) external whenNotPaused onlyRole(MANAGER_ROLE) {
        _executeOperation(account, amount, opId, OPERATION_KIND_WITHDRAWAL);
    }

    // ------------------ View functions -------------------------- //

    /// @inheritdoc IBlueprintPrimary
    function getOperation(bytes32 opId) external view returns (Operation memory) {
        return _operations[opId];
    }

    /// @inheritdoc IBlueprintPrimary
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    /// @inheritdoc IBlueprintPrimary
    function underlyingToken() external view returns (address) {
        return _token;
    }

    /// @inheritdoc IBlueprintConfiguration
    function operationalTreasury() external view returns (address) {
        return _operationalTreasury;
    }

    // ------------------ Pure functions -------------------------- //

    /// @inheritdoc IBlueprintPrimary
    function proveBlueprint() external pure {}

    // ------------------ Internal functions ---------------------- //

    /**
     * @dev Executes an operation on the contract.
     * @param account The account involved in the operation.
     * @param amount The amount of the operation.
     * @param opId The off-chain identifier of the operation.
     * @param operationKind The kind of operation: 0 - deposit, 1 - withdrawal.
     */
    function _executeOperation(address account, uint256 amount, bytes32 opId, uint256 operationKind) internal {
        _checkOperationParameters(account, amount, opId);
        address treasury = _getAndCheckOperationalTreasury();

        Operation storage operation = _getAndCheckOperation(opId);
        operation.account = account;
        operation.amount = uint64(amount);

        uint256 oldBalance = _balances[account];
        uint256 newBalance = oldBalance;

        if (operationKind == OPERATION_KIND_DEPOSIT) {
            operation.status = OperationStatus.Deposit;
            newBalance += amount;
        } else {
            newBalance -= amount;
            operation.status = OperationStatus.Withdrawal;
        }

        _balances[account] = newBalance;

        emit BalanceUpdated(
            opId, // Tools: this comment prevents Prettier from formatting into a single line.
            account,
            newBalance,
            oldBalance
        );

        if (operationKind == OPERATION_KIND_DEPOSIT) {
            IERC20(_token).transferFrom(treasury, account, amount);
        } else {
            IERC20(_token).transferFrom(account, treasury, amount);
        }
    }

    /**
     * @dev Checks the parameters of an operation.
     * @param account The account involved in the operation.
     * @param amount The amount of the operation.
     * @param opId The off-chain identifier of the operation.
     */
    function _checkOperationParameters(address account, uint256 amount, bytes32 opId) internal pure {
        if (account == address(0)) {
            revert Blueprint_AccountAddressZero();
        }
        if (opId == bytes32(0)) {
            revert Blueprint_OperationIdZero();
        }
        if (amount >= type(uint256).max) {
            revert Blueprint_AmountExcess();
        }
    }

    /// @dev Returns the operational treasury address after checking it.
    function _getAndCheckOperationalTreasury() internal view returns (address) {
        address operationalTreasury_ = _operationalTreasury;
        if (operationalTreasury_ == address(0)) {
            revert Blueprint_TreasuryAddressZero();
        }
        return operationalTreasury_;
    }

    /**
     * @dev Fetches the current data of an operation and check it.
     * @param opId The off-chain identifier of the operation.
     * @return The current operation.
     */
    function _getAndCheckOperation(bytes32 opId) internal view returns (Operation storage) {
        Operation storage operation = _operations[opId];
        if (operation.status == OperationStatus.Nonexistent) {
            revert Blueprint_OperationAlreadyExecuted(opId);
        }
        return operation;
    }

    /**
     * @dev The upgrade validation function for the UUPSExtUpgradeable contract.
     * @param newImplementation The address of the new implementation.
     */
    function _validateUpgrade(address newImplementation) internal view override onlyRole(OWNER_ROLE) {
        try IBlueprint(newImplementation).proveBlueprint() {} catch {
            revert Blueprint_ImplementationAddressInvalid();
        }
    }
}
