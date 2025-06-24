// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./interfaces/IERC20Hook.sol";

/**
 * @title ISharedWallet interface
 * @author CloudWalk Inc.
 * @notice Interface for the SharedWallet contract that integrates with BRLC token hooks
 */
interface ISharedWallet is IERC20Hook {
    enum SharedWalletStatus {
        Nonexistent,
        Active,
        Deactivated
    }

    enum BalanceOperationKind {
        Unknown,
        Deposit,
        Withdrawal,
        Transfer
    }

    enum ParticipantOperationKind { // TODO: Check value names
        Unknown,
        Addition,
        Removal
    }

    struct Participant {
        address participant;
        uint64 balance;
        uint32 reserve1;
        uint256 reserve2;
        uint256 reserve3;
        uint256 reserve4;
        uint256 reserve5;
        uint256 reserve6;
        uint256 reserve7;
    }

    struct ParticipantInfo {
        uint256 balance; // TODO: uint64
    }

    // Structs
    // in participant the first address is always the initiator of the wallet.
    struct SharedWallet {
        SharedWalletStatus status;
        uint256 totalBalance; // TODO: 1. Use `uint64`. 2. Rename, options: `balance`, `sharedBalance`.
        // TODO: 1. Can be merged with the participantInfo into a single struct. 2. Consider `EnumerableSet.AddressSet`.
        address[] participants; // TODO: consider 0 participant as the initiator and its special conditions
        mapping(address => ParticipantInfo) participantInfo;
        Participant[] _participants;
    }

    // Events
    event WalletCreated(address indexed wallet, address[] participants);
    event WalletDeactivated(address indexed wallet); // TODO:

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
    error SharedWallet_ZeroAddress();
    error SharedWallet_EmptyParticipants();
    error SharedWallet_WalletAlreadyExists();
    error SharedWallet_WalletNotExists(); // TODO: rename, options: "WalletNonExistent", "WalletAbsence".
    error SharedWallet_ParticipantAlreadyExists();
    error SharedWallet_ParticipantHasBalance(); // TODO: add the participant address parameter
    error SharedWallet_ParticipantInsufficientBalance(); // TODO: add paremeters
    error SharedWallet_WalletInsufficientBalance(); // TODO: add paremeters
    error SharedWallet_UnauthorizedToken();
    error SharedWallet_InvalidShareCalculation();

    // Admin functions
    function createWallet(address wallet, address[] calldata participants) external;

    function addParticipant(address wallet, address participant) external;

    function removeParticipant(address wallet, address participant) external;

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
 * @title SharedWalletVault
 * @author CloudWalk Inc.
 * @notice A secure vault contract that manages shared wallets and integrates with ERC20 token hooks
 */

// TODO: We need a better name here, because `vault` is associated with another share ownership mechanism.
contract SharedWalletVault is ISharedWallet, AccessControl {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Constants
    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // State variables
    IERC20 private immutable _token;
    mapping(address => SharedWallet) private _wallets;
    // TODO: Maybe redundant or can be replaced by an array, because there should not be many wallets for a participant
    mapping(address => EnumerableSet.AddressSet) private _participantWallets;
    mapping(address => address[]) private _participantWallets2;

    constructor(address token_) {
        if (token_ == address(0)) revert SharedWallet_ZeroAddress();
        _token = IERC20(token_);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // TODO: Use OWNER_ROLE
        _grantRole(ADMIN_ROLE, msg.sender); // TODO: Redundant
    }

    // Admin functions
    function createWallet(
        address wallet,
        address[] calldata participants
    ) external onlyRole(ADMIN_ROLE) {
        if (wallet == address(0)) revert SharedWallet_ZeroAddress();
        if (participants.length == 0) revert SharedWallet_EmptyParticipants();
        if (_wallets[wallet].status != SharedWalletStatus.Nonexistent) revert SharedWallet_WalletAlreadyExists();

        SharedWallet storage sharedWallet = _wallets[wallet];
        sharedWallet.status = SharedWalletStatus.Active;

        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            if (participant == address(0)) revert SharedWallet_ZeroAddress();

            sharedWallet.participants.push(participant);
            sharedWallet.participantInfo[participant].balance = 0;
            _participantWallets[participant].add(wallet);
        }

        emit WalletCreated(wallet, participants);
    }

    function addParticipant(address wallet, address participant) external onlyRole(ADMIN_ROLE) {
        if (_wallets[wallet].status != SharedWalletStatus.Active) revert SharedWallet_WalletNotExists();
        if (participant == address(0)) revert SharedWallet_ZeroAddress();
        if (_wallets[wallet].participantInfo[participant].balance > 0) revert SharedWallet_ParticipantAlreadyExists();

        _wallets[wallet].participants.push(participant);
        _participantWallets[participant].add(wallet);

        emit WalletParticipantOperation(
            wallet,
            participant,
            ParticipantOperationKind.Addition
        );
    }

    function removeParticipant(address wallet, address participant) external onlyRole(ADMIN_ROLE) {
        SharedWallet storage sharedWallet = _wallets[wallet];
        if (sharedWallet.status == SharedWalletStatus.Nonexistent) revert SharedWallet_WalletNotExists();
        if (sharedWallet.participantInfo[participant].balance > 0) revert SharedWallet_ParticipantHasBalance();

        // TODO: add logic to prohibit removing of the wallet initiator (sharedWallet.participants[0])
        // TODO: move the following logic to an internal function to share with the future `removeWallet()` function.

        // Remove from participants array
        uint256 length = sharedWallet.participants.length;
        for (uint256 i = 0; i < length; i++) {
            if (sharedWallet.participants[i] == participant) {
                sharedWallet.participants[i] = sharedWallet.participants[length - 1];
                sharedWallet.participants.pop();
                break;
            }
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
        if (msg.sender != address(_token)) revert SharedWallet_UnauthorizedToken();
        if (amount == 0) return;

        if (_wallets[to].status != SharedWalletStatus.Nonexistent) {
            // Handle transfer to wallet
            _handleTransferToWallet(from, to, amount);
        }
        else if (_wallets[from].status != SharedWalletStatus.Nonexistent) {
            // Handle transfer from wallet
            _handleTransferFromWallet(from, to, amount);
        }
    }

    // Internal functions
    function _handleTransferToWallet(address from, address wallet, uint256 amount) internal {
        SharedWallet storage sharedWallet = _wallets[wallet];

        if (isWalletParticipant(wallet, from)) {
            // If sender is a participant, update only their balance

            ParticipantInfo storage participantInfo = sharedWallet.participantInfo[from];
            uint256 oldParticipantBalance = participantInfo.balance;
            uint256 newParticipantBalance = oldParticipantBalance += amount;
            uint256 oldWalletBalance = sharedWallet.totalBalance;
            uint256 newWalletBalance = oldParticipantBalance += amount;
            participantInfo.balance = newParticipantBalance;
            sharedWallet.totalBalance = newWalletBalance;
            emit WalletBalanceOperation(
                wallet,
                from, //participant,
                BalanceOperationKind.Deposit,
                newParticipantBalance,
                oldParticipantBalance,
                newWalletBalance,
                oldWalletBalance
            );
        }
        else {
            // If sender is not a participant, distribute proportionally
            _receiveProportionally(wallet, amount);
        }
    }

    function _handleTransferFromWallet(address wallet, address to, uint256 amount) internal {
        SharedWallet storage sharedWallet = _wallets[wallet];
        if (sharedWallet.totalBalance < amount) {
            revert SharedWallet_WalletInsufficientBalance();
        }

        if (isWalletParticipant(wallet, to)) {
            // If recipient is a participant and has sufficient balance, deduct from their balance

            ParticipantInfo storage participantInfo = sharedWallet.participantInfo[to];
            uint256 oldParticipantBalance = participantInfo.balance;
            if (oldParticipantBalance < amount) {
                revert SharedWallet_ParticipantInsufficientBalance();
            }
            uint256 newParticipantBalance = oldParticipantBalance - amount;
            uint256 oldWalletBalance = sharedWallet.totalBalance;
            uint256 newWalletBalance = oldParticipantBalance - amount;

            participantInfo.balance = newParticipantBalance;
            sharedWallet.totalBalance = newWalletBalance;

            emit WalletBalanceOperation(
                wallet,
                to, //participant,
                BalanceOperationKind.Deposit,
                newParticipantBalance,
                oldParticipantBalance,
                newWalletBalance,
                oldWalletBalance
            );
        }
        else {
            // Otherwise, deduct proportionally from all participants
            _spendProportionally(wallet, amount);
        }
    }

    function _receiveProportionally(address wallet, uint256 amount) internal {
        SharedWallet storage sharedWallet = _wallets[wallet];
        uint256 totalBalance = sharedWallet.totalBalance;
        address[] memory participants = sharedWallet.participants; // TODO: replace memory => storage
        uint256[] memory shares;
        uint256 participantCount = participants.length;

        if (totalBalance == 0) {
            // If wallet is empty, distribute equally

            uint256[] memory participantBalances = _createParticipantBalances(participantCount, 1); // new uint256[](participants.length);
            shares = _determineShares(amount, participantCount, participantBalances);
        }
        else {
            // Otherwise distribute proportionally to existing balances

            uint256[] memory participantBalances = _getParticipantBalances(sharedWallet);
            shares = _determineShares(amount, totalBalance, participantBalances);
        }
        {
            uint256 oldWalletBalance = sharedWallet.totalBalance;
            uint256 newWalletBalance = oldWalletBalance += amount;
            for (uint256 i = 0; i < participantCount; ++i) {
                uint256 share = shares[i];
                if (share > 0) {
                    address participant = participants[i];
                    uint256 oldParticipantBalance = sharedWallet.participantInfo[participants[i]].balance;
                    uint256 newParticipantBalance = oldWalletBalance + share;
                    emit WalletBalanceOperation(
                        wallet,
                        participant,
                        BalanceOperationKind.Transfer,
                        newParticipantBalance,
                        oldParticipantBalance,
                        newWalletBalance,
                        oldWalletBalance
                    );
                }
            }
        }
    }

    function _spendProportionally(address wallet, uint256 amount) internal {
        SharedWallet storage sharedWallet = _wallets[wallet];
        uint256 totalBalance = sharedWallet.totalBalance;
        uint256 participantCount = sharedWallet.participants.length;
        uint256[] memory participantBalances = _getParticipantBalances(sharedWallet);
        uint256[] memory shares = _determineShares(amount, totalBalance, participantBalances);
        {
            uint256 oldWalletBalance = sharedWallet.totalBalance;
            uint256 newWalletBalance = oldWalletBalance -= amount;
            for (uint256 i = 0; i < participantCount; ++i) {
                uint256 share = shares[i];
                if (share > 0) {
                    address participant = sharedWallet.participants[i];
                    uint256 oldParticipantBalance = sharedWallet.participantInfo[participant].balance;
                    uint256 newParticipantBalance = oldWalletBalance - share;
                    emit WalletBalanceOperation(
                        wallet,
                        participant,
                        BalanceOperationKind.Transfer,
                        newParticipantBalance,
                        oldParticipantBalance,
                        newWalletBalance,
                        oldWalletBalance
                    );
                }
            }
        }
    }

    
    function _getParticipantBalances(SharedWallet storage sharedWallet) internal view returns (uint256[] memory participantBalances) {
        address[] memory participants = sharedWallet.participants;
        uint256 participantCount = participants.length;
        participantBalances = new uint256[](participantCount);
        
        for (uint256 i = 0; i < participantCount; i++) {
            participantBalances[i] = sharedWallet.participantInfo[participants[i]].balance;
        }
    }

    function _createParticipantBalances(
        uint256 participantCount,
        uint256 balance
    ) internal pure returns (uint256[] memory participantBalances) {
        participantBalances = new uint256[](participantCount);
        for (uint256 i = 0; i < participantCount; i++) {
            participantBalances[i] = balance;
        }
    }

    function _determineShares(
        uint256 amount,
        uint256 totalBalance,
        uint256[] memory participantBalances
    ) internal pure returns (uint256[] memory shares) {
        shares = new uint256[](participantBalances.length);
        uint256 totalShares = 0;
        uint256 lastIndex;
        uint256 i = participantBalances.length;
        do {
            --i;
            uint256 participantBalance = participantBalances[i];
            if (participantBalance > 0) {
                uint256 share = amount * participantBalance / totalBalance;
                totalShares += share;
                shares[i] = share;
                lastIndex = i;
            }
        } while(i != 0);
        shares[lastIndex] += amount - totalShares;
    }

    // View functions
    function getWalletInfo(
        address wallet
    ) external view returns (address[] memory participants, uint256[] memory balances) {
        SharedWallet storage sharedWallet = _wallets[wallet];
        participants = sharedWallet.participants;
        balances = new uint256[](participants.length);

        for (uint256 i = 0; i < participants.length; i++) {
            balances[i] = sharedWallet.participantInfo[participants[i]].balance;
        }
    }

    function getParticipantBalance(address wallet, address participant) external view returns (uint256) {
        return _wallets[wallet].participantInfo[participant].balance;
    }

    function getParticipantWallets( //TODO: rename, options: `getWalletsOfParticipant()`, getWalletsForParticipant()
        address participant
    ) external view returns (address[] memory wallets) {
        return _participantWallets[participant].values();
    }

    // TODO: rename, options: `isParticipant()`
    function isWalletParticipant(address wallet, address participant) public view returns (bool) {
        if (_wallets[wallet].status == SharedWalletStatus.Active) return false;
        return _participantWallets[participant].contains(wallet);
    }
}