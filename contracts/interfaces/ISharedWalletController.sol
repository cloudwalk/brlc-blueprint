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
     *  - 1. Any transfers to or from the wallet will cause the transaction to revert.
     *  - 2. Only a wallet with the zero balance can be deactivated.
     *  - 3. It is not possible to reactivate a deactivated wallet.
     */
    enum SharedWalletStatus {
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
     * @dev Possible operations with the balance in a shared wallet.
     *
     * The values:
     *
     * - Unknown = 0 ------ The operation is unknown (the default value).
     * - Deposit = 1 ------ A participant has deposited tokens to the wallet.
     * - Withdrawal = 2 --- A participant has withdrawn tokens from the wallet.
     * - TransferIn = 3 --- Tokens have been transferred to the wallet and distributed proportionally among participants.
     * - TransferOut = 4 -- Tokens have been transferred from the wallet and distributed proportionally among participants.
     */
    enum BalanceOperationKind {
        Unknown,
        Deposit,
        Withdrawal,
        TransferIn,
        TransferOut
    }

    /**
     * @dev Possible operations with a participant in a shared wallet.
     *
     * The values:
     *
     * - Unknown = 0 ----- The operation is unknown (the default value).
     * - Addition = 1 ---- A new participant has been added to the wallet.
     * - Removal = 2 ----- A participant has been removed from the wallet.
     */
    enum ParticipantOperationKind {
        Unknown,
        Addition,
        Removal
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
     * - status ------------- The status of the wallet according to the {SharedWalletStatus} enum.
     * - totalBalance ------- The total balance of the wallet.
     * - participants ------- The addresses of the participants in the wallet.
     * - participantStates -- The states of the participants in the wallet.
     */
    struct SharedWallet {
        // Slot 1
        SharedWalletStatus status;
        uint64 totalBalance; // TODO: 1. Use `uint64`. 2. Rename, options: `balance`, `sharedBalance`.
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
     *  - 1. The zero addresses in the struct are used as a wildcard.
     *  - 2. The wallet address can be zero, in this case all wallets with the provided participant address will be returned.
     *  - 3. The participant address can be zero, in this case all participants with the provided wallet will be returned.
     *  - 4. The wallet address and the participant address must not be zero at the same time.
     *  - 5. Extention of the pairs with the zero addresses is called normalization.
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
     * - wallet ------- The address of the wallet.
     * - status ------- The status of the participant according to the {ParticipantStatus} enum.
     * - index -------- The index of the participant address in the wallet.
     * - participant -- The address of the participant.
     * - balance ------ The balance of the participant in the wallet.
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
     * @dev Emitted when a new wallet is created.
     * @param wallet The address of the created wallet.
     */
    event WalletCreated(address indexed wallet);

    /**
     * @dev Emitted when the status of a wallet is changed.
     * @param wallet The address of the wallet.
     * @param newStatus The new status of the wallet.
     * @param oldStatus The old status of the wallet.
     */
    event WalletStatusChanged(
        address indexed wallet,
        // TODO: use type uint256 for enum fields?
        SharedWalletStatus indexed newStatus,
        SharedWalletStatus oldStatus
    );

    /**
     * @dev Emitted when a participant is added or removed from a wallet.
     * @param wallet The address of the wallet.
     * @param participant The address of the participant.
     * @param kind The kind of operation.
     */
    event WalletParticipantOperation(
        address indexed wallet,
        address indexed participant,
        // TODO: use type uint256 for enum fields?
        ParticipantOperationKind indexed kind
    );

    /**
     * @dev Emitted when the balance of a participant in a wallet is changed.
     * @param wallet The address of the wallet.
     * @param participant The address of the participant.
     * @param kind The kind of operation.
     * @param newParticipantBalance The new balance of the participant.
     */
    event WalletBalanceOperation(
        address indexed wallet,
        address indexed participant,
        // TODO: use type uint256 for enum fields?
        BalanceOperationKind indexed kind,
        uint256 newParticipantBalance,
        uint256 oldParticipantBalance,
        uint256 newWalletBalance,
        uint256 oldWalletBalance
    );

    // ------------------ Transactional functions ----------------- //

    /**
     * @dev Creates a new wallet.
     * @param wallet The address of the wallet.
     * @param participants The addresses of the participants.
     */
    function createWallet(address wallet, address[] calldata participants) external;

    /**
     * @dev Deactivates a wallet.
     * @param wallet The address of the wallet.
     */
    function deactivateWallet(address wallet) external;

    /**
     * @dev Activates a wallet.
     * @param wallet The address of the wallet.
     */
    function activateWallet(address wallet) external; // TODO: rename to `reactivateWallet()`

    /**
     * @dev Removes a wallet and all its participants. The result state is the same as if the wallet was never created.
     * @param wallet The address of the wallet.
     */
    function removeWallet(address wallet) external;

    /**
     * @dev Adds participants to a wallet.
     * @param wallet The address of the wallet.
     * @param participants The addresses of the participants.
     */
    function addParticipants(address wallet, address[] calldata participants) external;

    /**
     * @dev Removes participants from a wallet.
     * @param wallet The address of the wallet.
     * @param participants The addresses of the participants.
     */
    function removeParticipants(address wallet, address[] calldata participants) external;

    // ------------------ View functions --------------------------- //

    /**
     * @dev Returns the states of the participants in the wallets.
     *
     * A wildcard can be used in the pairs to get the states for all participants or all wallets,
     * see details in the {WalletParticipantPair} struct.
     *
     * @param participantWalletPairs The pairs of participants and wallets to get the states for.
     * @return participantStates The states of the participants in the wallets.
     */
    function getParticipantStates(
        WalletParticipantPair[] calldata participantWalletPairs
    ) external view returns (ParticipantStateView[] memory participantStates);

    /**
     * @dev Returns the wallets of a participant.
     * @param participant The address of the participant.
     * @return wallets The addresses of the wallets of the participant.
     */
    function getWallets(address participant) external view returns (address[] memory wallets);

    /**
     * @dev Returns the participants of a wallet.
     * @param wallet The address of the wallet.
     * @return participants The addresses of the participants of the wallet.
     */
    function getParticipants(address wallet) external view returns (address[] memory participants);

    /**
     * @dev Returns the balance of a participant in a wallet.
     * @param wallet The address of the wallet.
     * @param participant The address of the participant.
     * @return balance The balance of the participant in the wallet.
     */
    function getParticipantBalance(address wallet, address participant) external view returns (uint256 balance);

    /**
     * @dev Returns true if a participant is in a wallet.
     * @param wallet The address of the wallet.
     * @param participant The address of the participant.
     * @return True if the participant is in the wallet, false otherwise.
     */
    function isParticipant(address wallet, address participant) external view returns (bool);
}

/**
 * @title ISharedWalletControllerErrors interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev The errors of the shared wallet controller smart contract.
 */
interface ISharedWalletControllerErrors is ISharedWalletControllerTypes {
    // ------------------ Errors ---------------------------------- //
    /// @dev Thrown if the provided implementation address is invalid.
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
        SharedWalletStatus actualStatus,
        SharedWalletStatus compatibleStatus
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
