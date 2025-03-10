// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { Blueprint } from "../Blueprint.sol";

/**
 * @title Blueprint contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev The version of the blueprint contract with additions required for testing.
 * @custom:oz-upgrades-unsafe-allow missing-initializer
 */
contract BlueprintTestable is Blueprint {
    /**
     * @dev Sets the state of an account.
     * @param account The account to set the state of.
     * @param newState The new state of the account.
     */
    function setAccountState(address account, AccountState calldata newState) public {
        _accountStates[account] = newState;
    }
}
