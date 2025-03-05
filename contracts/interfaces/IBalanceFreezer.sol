// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IBalanceFreezerTypes } from "./IBalanceFreezerTypes.sol";

/**
 * @title IBalanceFreezerErrors interface
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev Defines the custom errors used in the balance freezer contract.
 */
interface IBalanceFreezerErrors {
    /**
     * @dev Thrown if the operation with the provided `txId` is already executed.
     * @param txId The provided off-chain transaction identifier of the related operation.
     */
    error BalanceFreezer_AlreadyExecuted(bytes32 txId);

    /**
     * @dev Thrown if the provided amount exceeds the maximum allowed value.
     * @param amount The provided amount.
     */
    error BalanceFreezer_AmountExcess(uint256 amount);

    /// @dev Thrown if the provided new implementation address is not of a balance freezer contract.
    error BalanceFreezer_ImplementationAddressInvalid();

    /// @dev Thrown if the provided token address is zero.
    error BalanceFreezer_TokenAddressZero();

    /// @dev Thrown if the provided off-chain transaction identifier is zero.
    error BalanceFreezer_TxIdZero();
}

/**
 * @title IBalanceFreezerPrimary interface
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev The primary interface of the balance freezer contract.
 */
interface IBalanceFreezerPrimary is IBalanceFreezerTypes {
    // ------------------ Events ---------------------------------- //

    /**
     * @dev Emitted when the frozen balance of a specific account has been updated.
     *
     * The balance update can happen due to a related update operation or because of a transfer operation.
     *
     * @param account The account whose frozen balance has been updated.
     * @param newFrozenBalance The updated frozen balance of the account.
     * @param oldFrozenBalance The previous frozen balance of the account.
     * @param txId The off-chain identifier of the transaction that caused the frozen balance update.
     */
    event FrozenBalanceUpdated(
        address indexed account,
        uint256 newFrozenBalance,
        uint256 oldFrozenBalance,
        bytes32 indexed txId
    );

    /**
     * @dev Emitted when a frozen tokens transfer operation have been executed.
     *
     * This event is accompanied by a corresponding event {FrozenBalanceUpdated},
     * since the transfer reduces the frozen balance of the source account.
     *
     * @param from The account from which the frozen tokens have been transferred.
     * @param to The account to which the frozen tokens have been transferred.
     * @param amount The amount of the transferred frozen tokens.
     * @param txId The off-chain identifier of the transaction that caused the transfer.
     */
    event FrozenBalanceTransfer(
        address indexed from, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 amount,
        bytes32 indexed txId,
        address indexed to
    );

    // ------------------ Functions ------------------------------- //

    /**
     * @dev Updates the frozen balance of an account.
     *
     * Emits a {FrozenBalanceUpdated} event.
     *
     * @param account The account to update the frozen balance for.
     * @param amount The amount of tokens to set as the new frozen balance.
     * @param txId The off-chain identifier of the balance frozen updating operation.
     */
    function freeze(
        address account, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 amount,
        bytes32 txId
    ) external;

    /**
     * @dev Increases the frozen balance of an account.
     *
     * Emits a {FrozenBalanceUpdated} event.
     *
     * @param account The account to increase frozen balance for.
     * @param amount The amount to increase the frozen balance by.
     * @param txId The off-chain identifier of the balance frozen updating operation.
     */
    function freezeIncrease(
        address account, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 amount,
        bytes32 txId
    ) external;

    /**
     * @dev Decreases the frozen balance of an account.
     *
     * Emits a {FrozenBalanceUpdated} event.
     *
     * @param account The account to decrease frozen balance for.
     * @param amount The amount to decrease the frozen balance by.
     * @param txId The off-chain identifier of the balance frozen updating operation.
     */
    function freezeDecrease(
        address account, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 amount,
        bytes32 txId
    ) external;

    /**
     * @dev Transfers frozen tokens on behalf of an account.
     *
     * The transfer decreases the frozen balance of the account by the transferred amount.
     *
     * Emits a {FrozenBalanceTransfer} event and a {FrozenBalanceUpdated} event.
     *
     * @param from The account whose tokens will be transferred from.
     * @param to The account whose tokens will be transferred to.
     * @param amount The amount of tokens to transfer.
     * @param txId The off-chain identifier of the transfer operation.
     */
    function transferFrozen(
        address from, // Tools: this comment prevents Prettier from formatting into a single line.
        address to,
        uint256 amount,
        bytes32 txId
    ) external;

    /**
     * @dev Returns the data of a single freezing operation.
     * @param txId The off-chain transaction identifier of the operation.
     * @return operation The data of the freezing operation in the form of a structure.
     */
    function getOperation(bytes32 txId) external view returns (Operation memory operation);

    /**
     * @dev Retrieves the frozen balance of an account.
     *
     * @param account The account to check the balance of.
     * @return The amount of tokens that are frozen for the account.
     */
    function balanceOfFrozen(address account) external view returns (uint256);

    /**
     * @dev Returns the address of the underlying token contract.
     */
    function underlyingToken() external view returns (address);

    /**
     * @dev Proves the contract is the balance freezer one. A marker function.
     */
    function proveBalanceFreezer() external pure;
}

/**
 * @title IBalanceFreezer interface
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev The full interface of the balance freezer contract.
 */
interface IBalanceFreezer is IBalanceFreezerErrors, IBalanceFreezerPrimary {}
