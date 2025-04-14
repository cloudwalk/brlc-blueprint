// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IAssetLiabilityTypes } from "./IAssetLiabilityTypes.sol";

/**
 * @title AssetLiabilityStorage abstract contract
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev Defines the storage layout for the asset liability contract.
 */
abstract contract AssetLiabilityStorage is IAssetLiabilityTypes {
    // Slot 1

    /// @dev The address of the underlying token contract.
    address internal _token;
    // uint96 __reserved1; // Reserved for future use until the end of the storage slot

    // Slot 2

    /// @dev The address of the operational treasury.
    address internal _treasury;
    // uint96 __reserved2; // Reserved for future use until the end of the storage slot

    // Slot 3

    /// @dev The total liability of all accounts.
    uint256 internal _totalLiability;

    // Slot 4

    /// @dev The mapping of a liability for a given account.
    mapping(address account => Liability liability) internal _liabilities;

    // Slots 5-50

    /// @dev Gap for future storage variables in upgradeable contracts.
    uint256[46] private __gap;
}
