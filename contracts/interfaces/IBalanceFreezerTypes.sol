// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title IBalanceFreezerTypes interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the types used in the balance freezer contracts.
 */
interface IBalanceFreezerTypes {
    /**
     * @dev Possible statuses of a balance freezing operation.
     *
     * The values:
     *
     * - Nonexistent = 0 ---------------- The operation does not exist (the default value).
     * - TransferExecuted = 1 ----------- The frozen balance transfer operation was executed.
     * - UpdateIncreaseExecuted = 2 ----- The frozen balance update by increasing operation was executed.
     * - UpdateDecreaseExecuted = 3 ----- The frozen balance update by decreasing operation was executed.
     * - UpdateReplacementExecuted = 4 -- The frozen balance update by replacement operation was executed.
     */
    enum OperationStatus {
        Nonexistent,
        TransferExecuted,
        UpdateIncreaseExecuted,
        UpdateDecreaseExecuted,
        UpdateReplacementExecuted
    }

    /**
     * @dev Structure with data of a single freezing operation.
     *
     * The fields:
     *
     * - status --- The status of the operation according to the {Status} enum.
     * - account -- The address of the account whose frozen balance was updated or transferred from.
     * - amount --- The amount parameter of the related operation.
     */
    struct Operation {
        OperationStatus status;
        address account;
        uint64 amount;
        // uint24 __reserved; // Reserved for future use until the end of the storage slot.
    }
}
