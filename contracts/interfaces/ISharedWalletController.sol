// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title ISharedWalletControllerTypes interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the types used in the shared wallet controller smart contract.
 */
interface ISharedWalletControllerTypes {
    /**
     * @dev Possible statuses of a shared wallet.
     *
     * The values:
     *
     * - Nonexistent = 0 -- The shared wallet with the provided address does not exist (the default value).
     * - Active = 1 ------- The shared wallet is active.
     * - Deactivated = 2 -- The shared wallet is deactivated.
     *
     * Notes:
     *
     *  - 1. Any transfers to or from a deactivated wallet will cause the transaction to revert.
     *  - 2. Only a wallet with the zero balance can be deactivated.
     *  - 3. It is not possible to reactivate a deactivated wallet.
     */
    enum WalletStatus {
        Nonexistent,
        Active,
        Deactivated
    }

    /**
     * @dev Possible statuses of a participant in a shared wallet.
     *
     * The values:
     *
     * - Nonexistent = 0 -- The participant with the provided address does not exist in the wallet (the default value).
     * - Active = 1 ------- The participant is a part of the wallet.
     */
    enum ParticipantStatus {
        Nonexistent,
        Active
    }

    /**
     * @dev The state of a participant within a shared wallet to store in the contract.
     *
     * The fields:
     *
     * - status --- The status of the participant according to the {ParticipantStatus} enum.
     * - index ---- The index of the participant address in the wallet.
     * - balance -- The balance of the participant in the wallet.
     */
    struct ParticipantState {
        // Slot 1
        ParticipantStatus status;
        uint16 index;
        uint64 balance;
        // uint168 __reserved; // Reserved for future use until the end of the storage slot
    }

    /**
     * @dev The data of a shared wallet to store in the contract.
     *
     * The fields:
     *
     * - status ------------- The status of the wallet according to the {WalletStatus} enum.
     * - sharedBalance ------ The balance of the wallet that is shared among participants.
     * - participants ------- The addresses of the participants in the wallet.
     * - participantStates -- The states of the participants in the wallet.
     */
    struct SharedWallet {
        // Slot 1
        WalletStatus status;
        uint64 sharedBalance;
        // uint184__reserved; // Reserved for future use until the end of the storage slot

        // Slot 2
        address[] participants;
        // No reserve until the end of the storage slot

        // Slot 3
        mapping(address participant => ParticipantState) participantStates;
        // No reserve until the end of the storage slot
    }

    /**
     * @dev A pair of a wallet and a participant to use as a parameter of a view function.
     *
     * The fields:
     *
     * - wallet ------- The address of the wallet.
     * - participant -- The address of the participant.
     *
     * Notes:
     *
     *  - 1. The zero address in the struct is used as a wildcard.
     *  - 2. If the the wallet address is zero then all wallets with the provided participant address will be returned.
     *  - 3. If the participant address is zero then all participants with the provided wallet will be returned.
     *  - 4. The wallet address and the participant address must not be zero at the same time.
     *  - 5. Replacing of the pairs with the zero addresses is called normalization.
     */
    struct WalletParticipantPair {
        address wallet;
        address participant;
    }

    /**
     * @dev A view of a participant within a shared wallet to use as a return value of a view function.
     *
     * The fields:
     *
     * - wallet ------- The address of the shared wallet.
     * - status ------- The status of the participant according to the {ParticipantStatus} enum.
     * - index -------- The index of the participant address in the shared wallet.
     * - participant -- The address of the participant.
     * - balance ------ The balance of the participant in the shared wallet.
     */
    struct ParticipantStateView {
        address wallet;
        ParticipantStatus status;
        uint16 index;
        address participant;
        uint256 balance;
    }
}

/**
 * @title ISharedWalletControllerPrimary interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev The primary part of the shared wallet controller smart contract interface.
 */
interface ISharedWalletControllerPrimary is ISharedWalletControllerTypes {
    // ------------------ Events ---------------------------------- //

    /**
     * @dev Emitted when a new shared wallet is created and activated.
     * @param wallet The address of the created wallet.
     */
    event WalletCreated(address indexed wallet);

    /**
     * @dev Emitted when a shared wallet is deactivated.
     * @param wallet The address of the deactivated wallet.
     */
    event WalletDeactivated(address indexed wallet);

    /**
     * @dev Emitted when a shared wallet is activated after being deactivated.
     * @param wallet The address of the activated wallet.
     */
    event WalletActivated(address indexed wallet);

    /**
     * @dev Emitted when a shared wallet is removed.
     * @param wallet The address of the removed wallet.
     * @param oldStatus The status of the wallet before removal.
     */
    event WalletRemoved(address indexed wallet, WalletStatus oldStatus);

    /**
     * @dev Emitted when a participant is added to a shared wallet.
     * @param wallet The address of the wallet.
     * @param participant The address of the participant.
     */
    event ParticipantAdded(address indexed wallet, address indexed participant);

    /**
     * @dev Emitted when a participant is removed from a wallet.
     * @param wallet The address of the wallet.
     * @param participant The address of the participant.
     */
    event ParticipantRemoved(address indexed wallet, address indexed participant);

    // NOTE: The wallet balance operation events below have been split into separate ones because it simplifies them,
    //       makes them more readable, adds granularity. If we need to fetch the whole history of operations,
    //       we can use a database query like:
    //       ```sql
    //       SELECT * FROM logs
    //       WHERE logs.first_topic IN (<deposit_hash>, <withdrawal_hash>, <transfer_in_hash>, <transfer_out_hash>)
    //       ```

    /**
     * @dev Emitted when a participant has deposited tokens to a shared wallet.
     * @param wallet The address of the shared wallet.
     * @param participant The address of the participant.
     * @param newParticipantBalance The balance of the participant after the deposit.
     * @param oldParticipantBalance The balance of the participant before the deposit.
     * @param newWalletBalance The balance of the shared wallet after the deposit.
     * @param oldWalletBalance The balance of the shared wallet before the deposit.
     */
    event Deposit(
        address indexed wallet,
        address indexed participant,
        uint256 newParticipantBalance,
        uint256 oldParticipantBalance,
        uint256 newWalletBalance,
        uint256 oldWalletBalance
    );

    /**
     * @dev Emitted when a participant has withdrawn tokens from a shared wallet.
     * @param wallet The address of the shared wallet.
     * @param participant The address of the participant.
     * @param newParticipantBalance The balance of the participant after the withdrawal.
     * @param oldParticipantBalance The balance of the participant before the withdrawal.
     * @param newWalletBalance The new balance of the shared wallet.
     * @param oldWalletBalance The old balance of the shared wallet.
     */
    event Withdrawal(
        address indexed wallet,
        address indexed participant,
        uint256 newParticipantBalance,
        uint256 oldParticipantBalance,
        uint256 newWalletBalance,
        uint256 oldWalletBalance
    );

    /**
     * @dev Emitted when tokens have been transferred to a shared wallet with distribution among participants.
     *
     * This event is emitted for each participant in the wallet that balance has been changed.
     *
     * @param wallet The address of the shared wallet.
     * @param participant The address of the participant.
     * @param newParticipantBalance The balance of the participant after the transfer.
     * @param oldParticipantBalance The balance of the participant before the transfer.
     * @param newWalletBalance The new balance of the shared wallet.
     * @param oldWalletBalance The old balance of the shared wallet.
     */
    event TransferIn(
        address indexed wallet,
        address indexed participant,
        uint256 newParticipantBalance,
        uint256 oldParticipantBalance,
        uint256 newWalletBalance,
        uint256 oldWalletBalance
    );

    /**
     * @dev Emitted when tokens have been transferred from a shared wallet with distribution among participants.
     *
     * This event is emitted for each participant in the wallet that balance has been changed.
     *
     * @param wallet The address of the shared wallet.
     * @param participant The address of the participant.
     * @param newParticipantBalance The balance of the participant after the transfer.
     * @param oldParticipantBalance The balance of the participant before the transfer.
     * @param newWalletBalance The balance of the shared wallet after the transfer.
     * @param oldWalletBalance The balance of the shared wallet before the transfer.
     */
    event TransferOut(
        address indexed wallet,
        address indexed participant,
        uint256 newParticipantBalance,
        uint256 oldParticipantBalance,
        uint256 newWalletBalance,
        uint256 oldWalletBalance
    );

    // ------------------ Transactional functions ----------------- //

    /**
     * @dev Creates a new shared wallet.
     * @param wallet The address of the shared wallet to create.
     * @param participants The addresses of the participants.
     */
    function createWallet(address wallet, address[] calldata participants) external;

    /**
     * @dev Deactivates a shared wallet.
     * @param wallet The address of the shared wallet to deactivate.
     */
    function deactivateWallet(address wallet) external;

    /**
     * @dev Activates a shared wallet that was previously deactivated.
     * @param wallet The address of the shared wallet to activate.
     */
    function activateWallet(address wallet) external;

    /**
     * @dev Removes a shared wallet and all its participants. The result state is the same as if the wallet was never created.
     * @param wallet The address of the shared wallet to remove.
     */
    function removeWallet(address wallet) external;

    /**
     * @dev Adds participants to a shared wallet.
     * @param wallet The address of the shared wallet to add participants to.
     * @param participants The addresses of the participants.
     */
    function addParticipants(address wallet, address[] calldata participants) external;

    /**
     * @dev Removes participants from a shared wallet.
     * @param wallet The address of the shared wallet to remove participants from.
     * @param participants The addresses of the participants.
     */
    function removeParticipants(address wallet, address[] calldata participants) external;

    // ------------------ View functions --------------------------- //

    /**
     * @dev Returns the states of the participants in the shared wallets.
     *
     * A wildcard can be used in the input pairs to get the states for all participants or all wallets,
     * see details in the {WalletParticipantPair} struct.
     *
     * @param participantWalletPairs The pairs of wallets and participants to get the states for.
     * @return participantStates The states of the participants in the wallets.
     */
    function getParticipantStates(
        WalletParticipantPair[] calldata participantWalletPairs
    ) external view returns (ParticipantStateView[] memory participantStates);

    /**
     * @dev Returns the shared wallets that a participant is a part of.
     * @param participant The address of the participant.
     * @return wallets The addresses of the shared wallets of the participant.
     */
    function getWallets(address participant) external view returns (address[] memory wallets);

    /**
     * @dev Returns all participants of a shared wallet.
     * @param wallet The address of the shared wallet.
     * @return participants The addresses of all participants of the shared wallet.
     */
    function getParticipants(address wallet) external view returns (address[] memory participants);

    /**
     * @dev Returns the balance of a participant in a shared wallet.
     * @param wallet The address of the shared wallet to get the balance of.
     * @param participant The address of the participant to get the balance of.
     * @return balance The balance of the participant in the shared wallet.
     */
    function getParticipantBalance(address wallet, address participant) external view returns (uint256 balance);

    /**
     * @dev Checks if a participant is in a shared wallet.
     * @param wallet The address of the shared wallet to check.
     * @param participant The address of the participant to check.
     * @return True if the participant is in the shared wallet, false otherwise.
     */
    function isParticipant(address wallet, address participant) external view returns (bool);
}

/**
 * @title ISharedWalletControllerErrors interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev The errors of the shared wallet controller smart contract.
 */
interface ISharedWalletControllerErrors is ISharedWalletControllerTypes {
    /// @dev Thrown if the aggregated balance across all shared wallets exceeds the limit.
    error SharedWalletController_AggregatedBalanceExcess();

    /// @dev Thrown if the implementation address provided for the contract upgrade is invalid.
    error SharedWalletController_ImplementationAddressInvalid();

    /// @dev Thrown if the provided participant address is zero.
    error SharedWalletController_ParticipantAddressZero();

    /// @dev Thrown if the provided participant array is empty.
    error SharedWalletController_ParticipantArrayEmpty();

    /// @dev Thrown if the current participant balance is insufficient for the operation.
    error SharedWalletController_ParticipantBalanceInsufficient();

    /// @dev Thrown if the current participant balance is nonzero.
    error SharedWalletController_ParticipantBalanceNonzero(address participant);

    /// @dev Thrown if during the operation the number of participants in the wallet exceeds the limit.
    error SharedWalletController_ParticipantCountExcess();

    /// @dev Thrown if the provided participant already exists.
    error SharedWalletController_ParticipantExistentAlready();

    /// @dev Thrown if the provided participant does not exist.
    error SharedWalletController_ParticipantNonexistent(address participant);

    /// @dev Thrown if the provided participant is a shared wallet.
    error SharedWalletController_ParticipantIsSharedWallet();

    /// @dev Thrown if the provided participant is not allowed to be removed from the wallet.
    error SharedWalletController_ParticipantUnremovable(address participant);

    /// @dev Thrown if the provided token is unauthorized.
    error SharedWalletController_TokenUnauthorized();

    /// @dev Thrown if the provided wallet address is zero.
    error SharedWalletController_WalletAddressZero();

    /// @dev Thrown if the number of existing shared wallets exceeds the limit.
    error SharedWalletController_WalletCountExcess();

    /// @dev Thrown if the provided wallet already exists.
    error SharedWalletController_WalletExistentAlready();

    /// @dev Thrown if the current wallet balance is insufficient for the operation.
    error SharedWalletController_WalletBalanceInsufficient();

    /// @dev Thrown if the current wallet balance is nonzero.
    error SharedWalletController_WalletBalanceNonzero();

    /// @dev Thrown if the provided wallet does not exist.
    error SharedWalletController_WalletNonexistent();

    /// @dev Thrown if the provided wallet status is incompatible.
    error SharedWalletController_WalletStatusIncompatible(
        WalletStatus actualStatus,
        WalletStatus compatibleStatus
    );
}

/**
 * @title ISharedWalletController interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev The full interface of the shared wallet controller smart contract.
 */
interface ISharedWalletController is ISharedWalletControllerPrimary, ISharedWalletControllerErrors {
    /**
     * @dev Proves the contract is the shared wallet controller one. A marker function.
     *
     * It is used for simple contract compliance checks, e.g. during an upgrade.
     * This avoids situations where a wrong contract address is specified by mistake.
     */
    function proveSharedWalletController() external pure;
}
