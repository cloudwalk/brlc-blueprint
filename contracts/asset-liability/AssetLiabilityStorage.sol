// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { IAssetLiabilityTypes } from "./IAssetLiabilityTypes.sol";

/**
 * @title AssetLiabilityStorage abstract contract
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev Defines the storage layout for the asset liability contract.
 * @custom:storage-layout This implements ERC-7201 for namespaced storage layout.
 */
abstract contract AssetLiabilityStorage is IAssetLiabilityTypes {
    // ERC-7201: Namespaced Storage Layout
    // keccak256(abi.encode(uint256(keccak256("cloudwalk.storage.AssetLiability")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ASSET_LIABILITY_STORAGE_LOCATION =
        0x001934aaca09350fe8ff6b8c7d5f6fad3d991d48c50551d7ada75910817eec00;

    /**
     * @dev Storage structure for AssetLiability contract
     */
    struct AssetLiabilityData {
        // Slot 1
        /// @dev The address of the underlying token contract.
        address underlyingToken;
        // uint96 __reserved1; // Reserved for future use until the end of the storage slot

        // Slot 2
        /// @dev The address of the operational treasury.
        address operationalTreasury;
        // uint96 __reserved2; // Reserved for future use until the end of the storage slot

        // Slot 3
        /// @dev The total liability of all accounts.
        uint256 totalLiability;
        // Slot 4
        /// @dev The mapping of a liability for a given account.
        mapping(address account => Liability liability) liabilities;
    }

    /**
     * @dev Returns the storage slot location for the AssetLiabilityData struct
     */
    function _getAssetLiabilityStorage() internal pure returns (AssetLiabilityData storage data) {
        bytes32 position = ASSET_LIABILITY_STORAGE_LOCATION;
        assembly {
            data.slot := position
        }
    }
}
