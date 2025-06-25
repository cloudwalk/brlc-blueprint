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
    // in participant the first address is always the initiator of the wallet.
    struct SharedWallet {
        SharedWalletStatus status;
        uint256 totalBalance; // TODO: 1. Use `uint64`. 2. Rename, options: `balance`, `sharedBalance`.
        // TODO: 1. Can be merged with the participantInfo into a single struct. 2. Consider `EnumerableSet.AddressSet`.
        address[] participants; // TODO: consider 0 participant as the initiator and its special conditions
        uint256[] participantBalances;
    }

    // Events
    event WalletCreated(address indexed wallet);
    event WalletDeactivated(address indexed wallet);

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
    error SharedWallet_AddressZero();
    error SharedWallet_ParticipantAlreadyExists();
    error SharedWallet_ParticipantArrayEmpty();
    error SharedWallet_ParticipantHasBalance(); // TODO: add the participant address parameter
    error SharedWallet_ParticipantInsufficientBalance(); // TODO: add paremeters
    error SharedWallet_ParticipantNonExistent(); // TODO: add parameters
    error SharedWallet_TokenUnauthorized();
    error SharedWallet_WalletAlreadyExists();
    error SharedWallet_WalletDeactivated(); // TODO: add paremeters
    error SharedWallet_WalletInsufficientBalance(); // TODO: add paremeters
    error SharedWallet_WalletNotActive();
    error SharedWallet_WalletNonexistent();

    // Admin functions
    function createWallet(address wallet, address[] calldata participants) external;

    function deactivateWallet(address wallet) external;

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

    function isWalletParticipant(address wallet, address participant) external view returns (bool); // TODO: simplify name: `isParticipant`
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
    uint256 private constant NON_EXISTENT_PARTICIPANT_INDEX = type(uint256).max;

    // State variables
    IERC20 private immutable _token;
    mapping(address => SharedWallet) private _wallets;
    // TODO: Maybe redundant or can be replaced by an array, because there should not be many wallets for a participant
    mapping(address => EnumerableSet.AddressSet) private _participantWallets;
    mapping(address => address[]) private _participantWallets2;

    constructor(address token_) {
        if (token_ == address(0)) revert SharedWallet_AddressZero();
        _token = IERC20(token_);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // TODO: Use OWNER_ROLE
        _grantRole(ADMIN_ROLE, msg.sender); // TODO: Redundant
    }

    // Admin functions
    function createWallet(
        address wallet,
        address[] calldata participants
    ) external onlyRole(ADMIN_ROLE) {
        if (wallet == address(0)) revert SharedWallet_AddressZero();
        if (participants.length == 0) revert SharedWallet_ParticipantArrayEmpty();
        if (_wallets[wallet].status != SharedWalletStatus.Nonexistent) revert SharedWallet_WalletAlreadyExists();

        SharedWallet storage sharedWallet = _wallets[wallet];
        sharedWallet.status = SharedWalletStatus.Active;
        emit WalletCreated(wallet);

        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            _addParticipantToWallet(wallet, participant);
        }
    }

    function deactivateWallet(address wallet) external onlyRole(ADMIN_ROLE) {
        if (_wallets[wallet].status != SharedWalletStatus.Active) revert SharedWallet_WalletNotActive();
        _wallets[wallet].status = SharedWalletStatus.Deactivated;
        emit WalletDeactivated(wallet);
    }

    function addParticipants(address wallet, address[] calldata participants) external onlyRole(ADMIN_ROLE) {
        if (_wallets[wallet].status == SharedWalletStatus.Nonexistent) revert SharedWallet_WalletNonexistent();
        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            _addParticipantToWallet(wallet, participant);
        }
    }

    function _addParticipantToWallet(
        address wallet,
        address participant
    ) internal {
        if (participant == address(0)) revert SharedWallet_AddressZero();
        SharedWallet storage sharedWallet = _wallets[wallet];
        uint256 participantIndex = _getParticipantIndex(sharedWallet, participant);
        if (participantIndex != NON_EXISTENT_PARTICIPANT_INDEX) revert SharedWallet_ParticipantAlreadyExists();

        sharedWallet.participants.push(participant);
        sharedWallet.participantBalances.push();
        _participantWallets[participant].add(wallet);

        emit WalletParticipantOperation(
            wallet,
            participant,
            ParticipantOperationKind.Addition
        );
    }

    function removeParticipants(address wallet, address[] calldata participants) external onlyRole(ADMIN_ROLE) {
        if (_wallets[wallet].status == SharedWalletStatus.Nonexistent) revert SharedWallet_WalletNonexistent();
        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            _removeParticipantFromWallet(wallet, participant);
        }
    }

    function _removeParticipantFromWallet(address wallet, address participant) internal {
        SharedWallet storage sharedWallet = _wallets[wallet];
        uint256 participantIndex = _getParticipantIndex(sharedWallet, participant);
        if (participantIndex == NON_EXISTENT_PARTICIPANT_INDEX) revert SharedWallet_ParticipantNonExistent();
        if (sharedWallet.participantBalances[participantIndex] > 0) revert SharedWallet_ParticipantHasBalance();

        // TODO: add logic to prohibit removing of the wallet initiator (sharedWallet.participants[0])
        // TODO: move the following logic to an internal function to share with the future `removeWallet()` function.

        // Remove from arrays
        {
            uint256 lastIndex = sharedWallet.participants.length - 1;
            sharedWallet.participants[participantIndex] = sharedWallet.participants[lastIndex];
            delete sharedWallet.participants[lastIndex];
            sharedWallet.participants.pop();
            sharedWallet.participantBalances[participantIndex] = sharedWallet.participantBalances[lastIndex];
            delete sharedWallet.participantBalances[lastIndex];
            sharedWallet.participantBalances.pop();
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
            // Handle transfer from wallet
            _handleTransferFromWallet(from, to, amount);
        } else if (status == SharedWalletStatus.Deactivated) {
            revert SharedWallet_WalletDeactivated();
        }

        status = _wallets[to].status;
        if (status == SharedWalletStatus.Active) {
            // Handle transfer to wallet
            _handleTransferToWallet(from, to, amount);
        } else if (status == SharedWalletStatus.Deactivated) {
            revert SharedWallet_WalletDeactivated();
        }
    }

    function _handleTransferFromWallet(address wallet, address to, uint256 amount) internal {
        SharedWallet storage sharedWallet = _wallets[wallet];
        uint256 participantIndex = _getParticipantIndex(sharedWallet, to);

        if (participantIndex != NON_EXISTENT_PARTICIPANT_INDEX) {
            // If recipient is a participant and has sufficient balance, deduct from their balance
            _processFunding(wallet, participantIndex, amount, uint256(TransferKind.Spending));
        }
        else {
            // Otherwise, deduct proportionally from all participants
            _processTransfer(wallet, amount, uint256(TransferKind.Spending));
        }
    }

    // Internal functions
    function _handleTransferToWallet(address from, address wallet, uint256 amount) internal {
        SharedWallet storage sharedWallet = _wallets[wallet];
        uint256 participantIndex = _getParticipantIndex(sharedWallet, from);

        if (participantIndex != NON_EXISTENT_PARTICIPANT_INDEX) {
            // If sender is a participant, update only their balance
            _processFunding(wallet, participantIndex, amount, uint256(TransferKind.Receiving));
        }
        else {
            // If sender is not a participant, distribute proportionally
            _processTransfer(wallet, amount, uint256(TransferKind.Receiving));
        }
    }

    function _getParticipantIndex(
        SharedWallet storage sharedWallet,
        address participant
    ) internal view returns (uint256) {
        uint256 i = sharedWallet.participants.length;   
        do {
            --i;
            if (sharedWallet.participants[i] == participant) return i;
        }
        while (i != 0);
        return NON_EXISTENT_PARTICIPANT_INDEX;
    }

    function _processFunding(
        address wallet,
        uint256 participantIndex,
        uint256 amount,
        uint256 transferKind
    ) internal {
        SharedWallet storage sharedWallet = _wallets[wallet];
        uint256 oldWalletBalance = sharedWallet.totalBalance;
        uint256 newWalletBalance;
        uint256 oldParticipantBalance = sharedWallet.participantBalances[participantIndex];
        uint256 newParticipantBalance;
        if (transferKind == uint256(TransferKind.Receiving)) {
            newParticipantBalance = oldParticipantBalance + amount;
            newWalletBalance = oldWalletBalance + amount;
        } else {
            if (oldWalletBalance < amount) {
                revert SharedWallet_WalletInsufficientBalance();
            }
            if (oldParticipantBalance < amount) {
                revert SharedWallet_ParticipantInsufficientBalance();
            }
            newParticipantBalance = oldParticipantBalance - amount;
            newWalletBalance = oldWalletBalance - amount;
        }

        sharedWallet.participantBalances[participantIndex] = newParticipantBalance;
        sharedWallet.totalBalance = newWalletBalance;

        emit WalletBalanceOperation(
            wallet,
        sharedWallet.participants[participantIndex],
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
                revert SharedWallet_WalletInsufficientBalance();
            }
            newWalletBalance = oldWalletBalance - amount;
        }
        uint256[] memory shares = _determineShares(amount, sharedWallet);
        uint256 participantCount = sharedWallet.participants.length;

        sharedWallet.totalBalance = newWalletBalance;

        for (uint256 i = 0; i < participantCount; ++i) {
            uint256 share = shares[i];
            if (share > 0) {
                address participant = sharedWallet.participants[i];
                uint256 oldParticipantBalance = sharedWallet.participantBalances[i];
                uint256 newParticipantBalance = (transferKind == uint256(TransferKind.Receiving))
                    ? oldWalletBalance + share
                    : oldWalletBalance - share;
                sharedWallet.participantBalances[i] = newParticipantBalance;
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
                uint256 participantBalance = sharedWallet.participantBalances[i];
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
        balances = sharedWallet.participantBalances;
    }

    function getParticipantBalance(address wallet, address participant) external view returns (uint256) {
        SharedWallet storage sharedWallet = _wallets[wallet];
        uint256 participantIndex = _getParticipantIndex(sharedWallet, participant);
        if (participantIndex != NON_EXISTENT_PARTICIPANT_INDEX) {
            return sharedWallet.participantBalances[participantIndex];
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
        return _participantWallets[participant].contains(wallet);
    }
}