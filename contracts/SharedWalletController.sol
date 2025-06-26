// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IERC20Hook.sol";

/**
 * @title ISharedWalletController interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev The interface for the contract to manage shared wallets and integrate them with an ERC20 token through hooks.
 */
interface ISharedWalletController is IERC20Hook {
    enum SharedWalletStatus {
        Nonexistent,
        Active,
        Deactivated
    }

    enum ParticipantStatus {
        Nonexistent,
        Active
    }

    enum BalanceOperationKind {
        Unknown,
        Deposit,
        Withdrawal,
        TransferIn,
        TransferOut
    }

    enum ParticipantOperationKind {
        Unknown,
        Addition,
        Removal
    }

    enum TransferKind {
        Receiving,
        Spending
    }

    // Structs
    struct ParticipantState {
        ParticipantStatus status;
        uint16 index;
        uint256 balance;
    }

    // in participant the first address is always the initiator of the wallet.
    struct SharedWallet {
        SharedWalletStatus status;
        uint256 totalBalance; // TODO: 1. Use `uint64`. 2. Rename, options: `balance`, `sharedBalance`.
        address[] participants;
        mapping(address participant => ParticipantState) participantStates;
    }

    // Events
    event WalletCreated(address indexed wallet);

    event WalletStatusChanged(
        address indexed wallet,
        SharedWalletStatus indexed newStatus,
        SharedWalletStatus oldStatus
    );

    event WalletParticipantOperation(
        address indexed wallet,
        address indexed participant,
        ParticipantOperationKind indexed kind
    );

    event WalletBalanceOperation (
        address indexed wallet,
        address indexed participant,
        BalanceOperationKind indexed kind,
        uint256 newParticipantBalance,
        uint256 oldParticipantBalance,
        uint256 newWalletBalance,
        uint256 oldWalletBalance
    );

    // Custom errors
    error SharedWallet_ParticipantAddressZero();
    error SharedWallet_ParticipantArrayEmpty();
    error SharedWallet_ParticipantBalanceInsufficient(); // TODO: add paremeters
    error SharedWallet_ParticipantBalanceNonzero(address participant); // TODO: add the participant address parameter
    error SharedWallet_ParticipantExistentAlready();
    error SharedWallet_ParticipantNonexistent(); // TODO: add parameters
    error SharedWallet_TokenUnauthorized();
    error SharedWallet_WalletAddressZero();
    error SharedWallet_WalletExistentAlready();
    error SharedWallet_WalletBalanceInsufficient(); // TODO: add paremeters
    error SharedWallet_WalletBalanceNonzero();
    error SharedWallet_WalletNonexistent();
    error SharedWallet_WalletStatusIncompatible( // TODO: should we use uint256 instead?
        SharedWalletStatus actualStatus,
        SharedWalletStatus compatibleStatus
    );

    // Admin functions
    function createWallet(address wallet, address[] calldata participants) external;

    function deactivateWallet(address wallet) external;

    function activateWallet(address wallet) external;

    function removeWallet(address wallet) external;

    function addParticipants(address wallet, address[] calldata participants) external;

    function removeParticipants(address wallet, address[] calldata participants) external;

    // View functions
    function getWalletInfo(
        address wallet
    ) external view returns (address[] memory participants, uint256[] memory balances);

    function getParticipantBalance(address wallet, address participant) external view returns (uint256);

    function getParticipantWallets(
        address participant
    ) external view returns (address[] memory wallets);

    // TODO: simplify name: `isParticipant`
    function isWalletParticipant(address wallet, address participant) external view returns (bool);
}

/**
 * @title SharedWalletController contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Manages shared wallets and integrates them with an ERC20 token through hooks.
 */
contract SharedWalletController is ISharedWalletController, AccessControl {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Constants
    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 private constant OWNER_ROLE = keccak256("OWNER_ROLE");
    uint256 private constant NON_EXISTENT_PARTICIPANT_INDEX = type(uint256).max;

    // State variables
    IERC20 private immutable _token;
    mapping(address => SharedWallet) private _wallets;
    // TODO: Maybe redundant or can be replaced by an array, because there should not be many wallets for a participant
    mapping(address => EnumerableSet.AddressSet) private _participantWallets;

    constructor(address token_) {
        if (token_ == address(0)) revert SharedWallet_WalletAddressZero();
        _token = IERC20(token_);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // TODO: Use OWNER_ROLE
        _grantRole(ADMIN_ROLE, msg.sender); // TODO: Redundant
    }

    // Admin functions
    function createWallet(
        address wallet,
        address[] calldata participants
    ) external onlyRole(ADMIN_ROLE) {
        if (wallet == address(0)) revert SharedWallet_WalletAddressZero();
        if (participants.length == 0) revert SharedWallet_ParticipantArrayEmpty();
        SharedWallet storage sharedWallet = _wallets[wallet];
        if (sharedWallet.status != SharedWalletStatus.Nonexistent) {
            revert SharedWallet_WalletExistentAlready();
        }

        sharedWallet.status = SharedWalletStatus.Active;
        emit WalletCreated(wallet);
        emit WalletStatusChanged(wallet, SharedWalletStatus.Active, SharedWalletStatus.Nonexistent);

        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            _addParticipantToWallet(wallet, participant);
        }
    }

    function deactivateWallet(address wallet) external onlyRole(ADMIN_ROLE) {
        SharedWallet storage sharedWallet = _getExistentWallet(wallet);
        if (sharedWallet.status != SharedWalletStatus.Active) {
            revert SharedWallet_WalletStatusIncompatible(sharedWallet.status, SharedWalletStatus.Active);
        }
        if (sharedWallet.totalBalance > 0) revert SharedWallet_WalletBalanceNonzero();
        _wallets[wallet].status = SharedWalletStatus.Deactivated;
        emit WalletStatusChanged(wallet, SharedWalletStatus.Deactivated, SharedWalletStatus.Active);
    }

    function activateWallet(address wallet) external onlyRole(ADMIN_ROLE) {
        SharedWallet storage sharedWallet = _getExistentWallet(wallet);
        if (sharedWallet.status != SharedWalletStatus.Deactivated) {
            revert SharedWallet_WalletStatusIncompatible(
                sharedWallet.status,
                SharedWalletStatus.Deactivated
            );
        }
        sharedWallet.status = SharedWalletStatus.Active;
        emit WalletStatusChanged(wallet, SharedWalletStatus.Active, SharedWalletStatus.Deactivated);
    }

    function removeWallet(address wallet) external onlyRole(OWNER_ROLE) {
        SharedWallet storage sharedWallet = _getExistentWallet(wallet);
        if (sharedWallet.totalBalance > 0) revert SharedWallet_WalletBalanceNonzero();
        for (uint256 i = 0; i < sharedWallet.participants.length; i++) {
            _removeParticipantFromWallet(wallet, sharedWallet.participants[i]);
        }
        sharedWallet.status = SharedWalletStatus.Nonexistent;
        emit WalletStatusChanged(wallet, SharedWalletStatus.Nonexistent, sharedWallet.status);
    }

    function addParticipants(
        address wallet, 
        address[] calldata participants
    ) external onlyRole(ADMIN_ROLE) {
        _getExistentWallet(wallet);
        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            _addParticipantToWallet(wallet, participant);
        }
    }

    function _addParticipantToWallet(
        address wallet,
        address participant
    ) internal {
        if (participant == address(0)) revert SharedWallet_ParticipantAddressZero();
        SharedWallet storage sharedWallet = _wallets[wallet];
        if (sharedWallet.participantStates[participant].status != ParticipantStatus.Nonexistent) {
            revert SharedWallet_ParticipantExistentAlready();
        }

        // TODO: Prohibit use another shared wallet as a participant.

        // TODO: number of participants check.

        uint256 participantIndex = sharedWallet.participants.length;
        sharedWallet.participants.push(participant);
        ParticipantState storage state = sharedWallet.participantStates[participant];
        state.status = ParticipantStatus.Active;
        state.index = uint16(participantIndex);
        state.balance = 0;
        _participantWallets[participant].add(wallet);

        emit WalletParticipantOperation(
            wallet,
            participant,
            ParticipantOperationKind.Addition
        );
    }

    function removeParticipants(
        address wallet, 
        address[] calldata participants
    ) external onlyRole(ADMIN_ROLE) {
        _getExistentWallet(wallet);
        for (uint256 i = 0; i < participants.length; i++) {
            _removeParticipantFromWallet(wallet, participants[i]);
        }
    }

    function _removeParticipantFromWallet(
        address wallet, 
        address participant
    ) internal {
        SharedWallet storage sharedWallet = _wallets[wallet];
        if (sharedWallet.participantStates[participant].status == ParticipantStatus.Nonexistent) {
            revert SharedWallet_ParticipantNonexistent();
        }
        if (sharedWallet.participantStates[participant].balance > 0) {
            revert SharedWallet_ParticipantBalanceNonzero(participant);
        }

        // TODO: add logic to prohibit removing of the wallet initiator 
        // (sharedWallet.participants[0])

        // Remove from the array and clear storage
        {
            uint256 participantIndex = sharedWallet.participantStates[participant].index;
            uint256 lastIndex = sharedWallet.participants.length - 1;
            sharedWallet.participantStates[sharedWallet.participants[lastIndex]].index = uint16(participantIndex);
            sharedWallet.participants[participantIndex] = sharedWallet.participants[lastIndex];
            delete sharedWallet.participants[lastIndex];
            sharedWallet.participants.pop();
            delete sharedWallet.participantStates[participant];
        }

        _participantWallets[participant].remove(wallet);

        emit WalletParticipantOperation(
            wallet,
            participant,
            ParticipantOperationKind.Removal
        );
        
    }

    // Hook implementation
    function beforeTokenTransfer(address from, address to, uint256 amount) external {
        // No pre-transfer validation needed
    }

    function afterTokenTransfer(address from, address to, uint256 amount) external {
        if (msg.sender != address(_token)) revert SharedWallet_TokenUnauthorized();
        if (amount == 0) return;

        SharedWalletStatus status = _wallets[from].status;
        if (status == SharedWalletStatus.Active) {
            _handleTransferFromWallet(from, to, amount);
        } else if (status == SharedWalletStatus.Deactivated) {
            revert SharedWallet_WalletStatusIncompatible(SharedWalletStatus.Deactivated, SharedWalletStatus.Active);
        }

        status = _wallets[to].status;
        if (status == SharedWalletStatus.Active) {
            _handleTransferToWallet(from, to, amount);
        } else if (status == SharedWalletStatus.Deactivated) {
            revert SharedWallet_WalletStatusIncompatible(SharedWalletStatus.Deactivated, SharedWalletStatus.Active);
        }
    }

    function _handleTransferFromWallet(address wallet, address to, uint256 amount) internal {
        if (_wallets[wallet].participantStates[to].status == ParticipantStatus.Active) {
            _processFunding(wallet, to, amount, uint256(TransferKind.Spending));
        } else {
            _processTransfer(wallet, amount, uint256(TransferKind.Spending));
        }
    }

    // Internal functions
    function _getExistentWallet(address wallet) internal view returns (SharedWallet storage) {
        SharedWallet storage sharedWallet = _wallets[wallet];
        if (sharedWallet.status == SharedWalletStatus.Nonexistent) revert SharedWallet_WalletNonexistent();
        return sharedWallet;
    }

    function _handleTransferToWallet(address from, address wallet, uint256 amount) internal {
        if (_wallets[wallet].participantStates[from].status == ParticipantStatus.Active) {
            _processFunding(wallet, from, amount, uint256(TransferKind.Receiving));
        } else {
            _processTransfer(wallet, amount, uint256(TransferKind.Receiving));
        }
    }

    function _processFunding(
        address wallet,
        address participant,
        uint256 amount,
        uint256 transferKind
    ) internal {
        SharedWallet storage sharedWallet = _wallets[wallet];
        ParticipantState storage state = sharedWallet.participantStates[participant];
        uint256 oldWalletBalance = sharedWallet.totalBalance;
        uint256 newWalletBalance;
        uint256 oldParticipantBalance = state.balance;
        uint256 newParticipantBalance;
        if (transferKind == uint256(TransferKind.Receiving)) {
            newParticipantBalance = oldParticipantBalance + amount;
            newWalletBalance = oldWalletBalance + amount;
        } else {
            if (oldWalletBalance < amount) {
                revert SharedWallet_WalletBalanceInsufficient();
            }
            if (oldParticipantBalance < amount) {
                revert SharedWallet_ParticipantBalanceInsufficient();
            }
            newParticipantBalance = oldParticipantBalance - amount;
            newWalletBalance = oldWalletBalance - amount;
        }

        state.balance = newParticipantBalance;
        sharedWallet.totalBalance = newWalletBalance;

        emit WalletBalanceOperation(
            wallet,
        participant,
            transferKind == uint256(TransferKind.Receiving)
                ? BalanceOperationKind.Deposit
                : BalanceOperationKind.Withdrawal,
            newParticipantBalance,
            oldParticipantBalance,
            newWalletBalance,
            oldWalletBalance
        );
    }

    function _processTransfer(address wallet, uint256 amount, uint256 transferKind) internal {
        SharedWallet storage sharedWallet = _wallets[wallet];
        uint256 oldWalletBalance = sharedWallet.totalBalance;
        uint256 newWalletBalance;
        if (transferKind == uint256(TransferKind.Receiving)) {
            newWalletBalance = oldWalletBalance + amount;
        } else {
            if (oldWalletBalance < amount) {
                revert SharedWallet_WalletBalanceInsufficient();
            }
            newWalletBalance = oldWalletBalance - amount;
        }
        uint256[] memory shares = _determineShares(amount, sharedWallet);
        uint256 participantCount = sharedWallet.participants.length;

        sharedWallet.totalBalance = newWalletBalance;

        for (uint256 i = 0; i < participantCount; ++i) {
            if (shares[i] > 0) {
                address participant = sharedWallet.participants[i];
                ParticipantState storage state = sharedWallet.participantStates[participant];
                uint256 oldParticipantBalance = state.balance;
                uint256 newParticipantBalance = (transferKind == uint256(TransferKind.Receiving))
                    ? oldWalletBalance + shares[i]
                    : oldWalletBalance - shares[i];
                state.balance = newParticipantBalance;

                emit WalletBalanceOperation(
                    wallet,
                    participant,
                    transferKind == uint256(TransferKind.Receiving) 
                        ? BalanceOperationKind.TransferIn
                        : BalanceOperationKind.TransferOut,
                    newParticipantBalance,
                    oldParticipantBalance,
                    newWalletBalance,
                    oldWalletBalance
                );
            }
        }
    }

    function _determineShares(
        uint256 amount,
        SharedWallet storage sharedWallet
    ) internal view returns (uint256[] memory) {
        uint256 i = sharedWallet.participants.length;
        uint256[] memory shares = new uint256[](i);
        uint256 totalBalance = sharedWallet.totalBalance;
        uint256 totalShares = 0;
        uint256 lastNonZeroBalanceIndex = 0;
        if (totalBalance != 0) {
            do {
                --i;
                uint256 participantBalance = sharedWallet.participantStates[sharedWallet.participants[i]].balance;
                if (participantBalance > 0) {
                    uint256 share = _calculateShare(amount, participantBalance, totalBalance);
                    totalShares += share;
                    shares[i] = share;
                    lastNonZeroBalanceIndex = i;
                }
            }
            while (i != 0);
        } else {
            uint256 share = _calculateShare(amount, 1, i);
            totalShares = share * i;
            do {
                --i;
                shares[i] = share;
            }
            while (i != 0);
        }

        shares[lastNonZeroBalanceIndex] += amount - totalShares;
        return shares;
    }

    function _calculateShare(
        uint256 amount,
        uint256 balance,
        uint256 totalBalance
    ) internal pure returns (uint256) {
        return amount * balance / totalBalance; // TODO: Round to cents
    }

    // View functions
    function getWalletInfo(
        address wallet
    ) external view returns (address[] memory participants, uint256[] memory balances) {
        SharedWallet storage sharedWallet = _wallets[wallet];
        participants = sharedWallet.participants;
        balances = new uint256[](participants.length);

        for (uint256 i = 0; i < participants.length; i++) {
            balances[i] = sharedWallet.participantStates[participants[i]].balance;
        }
    }

    function getParticipantBalance(address wallet, address participant) external view returns (uint256) {
        ParticipantState storage state = _wallets[wallet].participantStates[participant];
        if (state.status == ParticipantStatus.Active) {
            return state.balance;
        } else {
            return 0;
        }
    }

    function getParticipantWallets( //TODO: rename, options: `getWalletsOfParticipant()`, getWalletsForParticipant()
        address participant
    ) external view returns (address[] memory wallets) {
        return _participantWallets[participant].values();
    }

    // TODO: rename, options: `isParticipant()`
    function isWalletParticipant(address wallet, address participant) public view returns (bool) {
        if (_wallets[wallet].status != SharedWalletStatus.Active) return false;
        return _wallets[wallet].participantStates[participant].status != ParticipantStatus.Nonexistent;
    }
}