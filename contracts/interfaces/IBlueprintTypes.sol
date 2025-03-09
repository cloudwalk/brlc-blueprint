// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title IBlueprintTypes interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the types used in the reference smart contract.
 *
 * See details about the contract in the comments of the {IBlueprint} interface.
 */
interface IBlueprintTypes {
    /**
     * @dev Possible statuses of a an operation used in the reference smart contract.
     *
     * The values:
     *
     * - Nonexistent = 0 -- The operation does not exist (the default value).
     * - Deposit = 1 ------ The deposit operation has been executed.
     * - Withdrawal = 2 --- The withdrawal operation has been executed.
     */
    enum OperationStatus {
        Nonexistent,
        Deposit,
        Withdrawal
    }

    /**
     * @dev The structure with data of a single operation of the reference smart-contract.
     *
     * The fields:
     *
     * - status --- The status of the operation according to the {OperationStatus} enum.
     * - account -- The address of the account involved in the operation.
     * - amount --- The amount parameter of the related operation.
     */
    struct Operation {
        OperationStatus status;
        address account;
        uint64 amount;
        // uint24 __reserved; // Reserved for future use until the end of the storage slot.
    }
}
