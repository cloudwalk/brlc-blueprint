// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title IAssetLiabilityPrimary interface
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev Defines the primary interface of the asset liability contract.
 */
interface IAssetLiabilityPrimary {
    // ------------------ Events----------------------------------- //
    /**
     * @dev Emitted when the liability of an account has been updated.
     *
     * @param account The account whose liability has been updated.
     * @param newLiability The new liability of the account.
     * @param oldLiability The previous liability of the account.
     */
    event LiabilityUpdated(address indexed account, uint256 newLiability, uint256 oldLiability);

    // ------------------ Transactional functions ----------------- //

    /**
     * @dev Transfers a specified amount of tokens to an account and increases the liability of the account.
     *
     * This function can be called only by an account with a special role.
     *
     * Emits multiple {LiabilityUpdated} events.
     *
     * @param accounts The accounts to transfer the tokens to.
     * @param amounts The amounts of tokens to transfer.
     */
    function transferWithLiability(address[] calldata accounts, uint256[] calldata amounts) external;

    /**
     * @dev Increases the liability of an account by a specified amount.
     *
     * This function can be called only by an account with a special role.
     *
     * Emits multiple {LiabilityUpdated} events.
     *
     * @param accounts The accounts to increase the liability for.
     * @param amounts The amounts to increase the liability by.
     */
    function increaseLiability(address[] calldata accounts, uint256[] calldata amounts) external;

    /**
     * @dev Reduces the liability of an account by a specified amount.
     *
     * This function can be called only by an account with a special role.
     *
     * Emits multiple {LiabilityUpdated} events.
     *
     * @param accounts The accounts to reduce the liability for.
     * @param amounts The amounts to reduce the liability by.
     */
    function reduceLiability(address[] calldata accounts, uint256[] calldata amounts) external;

    // ------------------ View functions -------------------------- //

    /**
     * @dev Returns the liability of an account.
     *
     * @param account The account to get the liability of.
     * @return The liability of the account.
     */
    function liabilityOf(address account) external view returns (uint256);

    /**
     * @dev Returns the total liability of all accounts.
     *
     * @return The total liability of all accounts.
     */
    function totalLiability() external view returns (uint256);
}

/**
 * @title IAssetLiabilityConfiguration interface
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev Defines the configuration interface of the asset liability contract.
 */
interface IAssetLiabilityConfiguration {
    // ------------------ Events ---------------------------------- //

    /**
     * @dev Emitted when the address of the operational treasury has been updated.
     *
     * @param newTreasury The new address of the operational treasury.
     * @param oldTreasury The previous address of the operational treasury.
     */
    event TreasuryUpdated(address indexed newTreasury, address indexed oldTreasury);

    // ------------------ Transactional functions ----------------- //

    /**
     * @dev Sets the address of the operational treasury.
     *
     * This function can be called only by an account with a special role.
     *
     * Emits a {TreasuryUpdated} event.
     *
     * @param treasury_ The address of the operational treasury.
     */
    function setOperationalTreasury(address treasury_) external;

    // ------------------ View functions -------------------------- //

    /**
     * @dev Returns the address of the operational treasury.
     *
     * @return The address of the operational treasury.
     */
    function operationalTreasury() external view returns (address);

    /**
     * @dev Returns the address of the underlying token contract.
     *
     * @return The address of the underlying token contract.
     */
    function underlyingToken() external view returns (address);
}

/**
 * @title IAssetLiabilityErrors interface
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev Defines the errors of the asset liability contract.
 */
interface IAssetLiabilityErrors {
    /// @dev Thrown if the implementation address is invalid during an upgrade.
    error AssetLiability_ImplementationAddressInvalid();

    /// @dev Thrown if the underlying token address provided is zero.
    error AssetLiability_UnderlyingTokenAddressZero();

    /// @dev Thrown if the treasury address provided is already set.
    error AssetLiability_TreasuryAddressAlreadySet();

    /// @dev Thrown if the accounts and amounts arrays have different lengths.
    error AssetLiability_AccountsAndAmountsLengthMismatch();

    /// @dev Thrown if the address of the account is zero.
    error AssetLiability_AccountAddressZero();

    /// @dev Thrown if the amount is zero when its not allowed.
    error AssetLiability_AmountZero();

    /// @dev Thrown if the reduction amount exceeds the current liability of an account.
    error AssetLiability_ReductionAmountExcess();
}

/**
 * @title IAssetLiability interface
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev The full interface of the asset liability contract.
 */
interface IAssetLiability is IAssetLiabilityPrimary, IAssetLiabilityConfiguration, IAssetLiabilityErrors {
    /**
     * @dev Proves the contract is the asset liability one.
     *
     * It is used for simple contract compliance checks, e.g. during an upgrade.
     * This avoids situations where a wrong contract address is specified by mistake.
     */
    function proveAssetLiability() external pure;
}
