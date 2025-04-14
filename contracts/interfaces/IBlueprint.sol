// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IBlueprintTypes } from "./IBlueprintTypes.sol";

/**
 * @title IBlueprintPrimary interface
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev The primary part of the blueprint smart contract interface.
 *
 * See details about the contract in the comments of the {IBlueprint} interface.
 */
interface IBlueprintPrimary is IBlueprintTypes {
    // ------------------ Events ---------------------------------- //

    /**
     * @dev Emitted when the balance of a specific account on the smart contract has been updated.
     *
     * The balance update can happen due to a deposit or withdrawal operation.
     *
     * @param opId The off-chain identifier of the operation.
     * @param account The account whose balance has been updated.
     * @param newBalance The updated balance of the account.
     * @param oldBalance The previous balance of the account.
     */
    event BalanceUpdated(
        bytes32 indexed opId, // Tools: this comment prevents Prettier from formatting into a single line
        address indexed account,
        uint256 newBalance,
        uint256 oldBalance
    );

    // ------------------ Transactional functions ----------------- //

    /**
     * @dev Deposits tokens to the smart-contract.
     *
     * During the function call the specified amount of tokens will be transferred from the caller to
     * the configured treasury of the contract and the balance of the provided account will be increased accordingly.
     *
     * This function can be called only by an account with a special role.
     *
     * Emits a {BalanceUpdated} event.
     *
     * @param account The account to increase balance for.
     * @param amount The amount to increase the balance by.
     * @param opId The off-chain identifier of the operation.
     */
    function deposit(
        address account, // Tools: this comment prevents Prettier from formatting into a single line
        uint256 amount,
        bytes32 opId
    ) external;

    /**
     * @dev Withdraws tokens from the smart-contract.
     *
     * During the function call the specified amount of tokens will be transferred back from
     * the configured treasury of the contract to the provided account and
     * the balance of the account will be decreased accordingly.
     *
     * This function can be called only by an account with a special role.
     *
     * Emits a {BalanceUpdated} event.
     *
     * @param account The account to decrease the balance for.
     * @param amount The amount to decrease the balance by.
     * @param opId The off-chain identifier of the operation.
     */
    function withdraw(
        address account, // Tools: this comment prevents Prettier from formatting into a single line
        uint256 amount,
        bytes32 opId
    ) external;

    // ------------------ View and pure functions ----------------- //

    /**
     * @dev Returns the data of a single operation on the smart-contract.
     * @param opId The off-chain identifier of the operation.
     * @return operation The data of the operation.
     */
    function getOperation(bytes32 opId) external view returns (Operation memory operation);

    /**
     * @dev Returns the state of an account.
     * @param account The account to get the state of.
     * @return state The state of the account.
     */
    function getAccountState(address account) external view returns (AccountState memory state);

    /**
     * @dev Retrieves the balance of an account.
     *
     * This function is a shortcut for `getAccountState().balance`.
     *
     * @param account The account to check the balance of.
     * @return The resulting amount of tokens that were transferred to the contract after all operations.
     */
    function balanceOf(address account) external view returns (uint256);

    /// @dev Returns the address of the underlying token contract.
    function underlyingToken() external view returns (address);

    /**
     * @dev Proves the contract is the blueprint one. A marker function.
     *
     * It is used for simple contract compliance checks, e.g. during an upgrade.
     * This avoids situations where a wrong contract address is specified by mistake.
     */
    function proveBlueprint() external pure;
}

/**
 * @title IBlueprintConfiguration interface
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev The configuration part of the blueprint smart contract interface.
 */
interface IBlueprintConfiguration {
    // ------------------ Events ---------------------------------- //

    /**
     * @dev Emitted when the operational treasury address has been changed.
     *
     * See the {operationalTreasury} view function comments for more details.
     *
     * @param newTreasury The updated address of the operational treasury.
     * @param oldTreasury The previous address of the operational treasury.
     */
    event OperationalTreasuryChanged(address newTreasury, address oldTreasury);

    // ------------------ Transactional functions ----------------- //

    /**
     * @dev Sets the operational treasury address.
     *
     * This function can be called only by an account with a special role.
     *
     * Emits an {OperationalTreasuryChanged} event.
     *
     * @param newTreasury The new address of the operational treasury to set.
     */
    function setOperationalTreasury(address newTreasury) external;

    // ------------------ View functions -------------------------- //

    /// @dev Returns the address of the operational treasury of this smart-contract.
    function operationalTreasury() external view returns (address);
}

/**
 * @title IBlueprintErrors interface
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev Defines the custom errors used in the blueprint contract.
 *
 * The errors are ordered alphabetically.
 */
interface IBlueprintErrors {
    /// @dev Thrown if the provided account address is zero.
    error Blueprint_AccountAddressZero();

    /// @dev Thrown if the provided amount is greater than the allowed maximum.
    error Blueprint_AmountExcess();

    /// @dev Thrown if the result account balance is greater than the allowed maximum.
    error Blueprint_BalanceExcess();

    /// @dev Thrown if the provided new implementation address is not of a blueprint contract.
    error Blueprint_ImplementationAddressInvalid();

    /**
     * @dev Thrown if the operation with the provided identifier is already executed.
     * @param opId The provided off-chain identifier of the related operation.
     */
    error Blueprint_OperationAlreadyExecuted(bytes32 opId);

    /// @dev Thrown if the provided off-chain operation identifier is zero.
    error Blueprint_OperationIdZero();

    /**
     * @dev Thrown if the provided underlying token address is zero.
     *
     * This error can be thrown during the contract initialization.
     */
    error Blueprint_TokenAddressZero();

    /// @dev Thrown if the provided treasury address is already configured.
    error Blueprint_TreasuryAddressAlreadyConfigured();

    /// @dev Thrown if the configured operational treasury address is zero, so token transfer operations are disabled.
    error Blueprint_OperationalTreasuryAddressZero();

    /// @dev Thrown if the provided treasury has not granted the contract allowance to spend tokens.
    error Blueprint_TreasuryAllowanceZero();
}

/**
 * @title IBlueprint interface
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev The full interface of the blueprint smart contract.
 *
 * The smart contract is designed as a reference and template one.
 * It allows to deposit or withdraw tokens with specifying an external (off-chain) identifier.
 * The contract itself does not store tokens on its account.
 * It uses an external storage called the operational treasury that can be configured by the owner of the contract.
 * The contract can be paused, in that case only configuration and non-transactional functions can be called.
 * Depositing, withdrawal, and similar functions are reverted if the contract is paused.
 *
 * Some logic and entities of this contract are just for demonstration purposes and do not have any real use.
 */
interface IBlueprint is IBlueprintPrimary, IBlueprintConfiguration, IBlueprintErrors {}
