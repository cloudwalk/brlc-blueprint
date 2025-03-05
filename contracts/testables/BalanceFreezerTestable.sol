// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { BalanceFreezer } from "../BalanceFreezer.sol";

/**
 * @title BalanceFreezer contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev The version of the balance freezer contract with additions required for testing.
 */
contract BalanceFreezerTestable is BalanceFreezer {
    /**
     * @dev Needed to check that the initialize function of the ancestor contract
     * has the 'onlyInitializing' modifier.
     */
    function call_parent_initialize(address token_) public {
        __BalanceFreezer_init(token_);
    }

    /**
     * @dev Needed to check that the unchained initialize function of the ancestor contract
     * has the 'onlyInitializing' modifier.
     */
    function call_parent_initialize_unchained(address token_) public {
        __BalanceFreezer_init_unchained(token_);
    }
}
