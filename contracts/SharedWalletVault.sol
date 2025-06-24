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
    // Structs
    struct SharedWallet {
        bool exists;
        address[] participants;
        mapping(address => ParticipantInfo) participantInfo;
        uint256 totalBalance;
    }

    struct ParticipantInfo {
        uint256 balance;
    }

    // Events
    event WalletCreated(address indexed wallet, address[] participants);
    event WalletParticipantAdded(address indexed wallet, address indexed participant);
    event WalletParticipantRemoved(address indexed wallet, address indexed participant);
    event WalletDeposit(address indexed wallet, address indexed participant, uint256 amount);
    event WalletWithdrawal(address indexed wallet, address indexed participant, uint256 amount);
    event SharedTransfer(address indexed wallet, address indexed sender, address indexed recipient, uint256 amount);

    // Custom errors
    error SharedWallet_ZeroAddress();
    error SharedWallet_EmptyParticipants();
    error SharedWallet_WalletAlreadyExists();
    error SharedWallet_WalletNotExists();
    error SharedWallet_ParticipantAlreadyExists();
    error SharedWallet_ParticipantHasBalance();
    error SharedWallet_UnauthorizedToken();
    error SharedWallet_InvalidShareCalculation();

    // Admin functions
    function createWallet(address wallet, address[] calldata participants) external returns (bool);

    function addParticipant(address wallet, address participant) external returns (bool);

    function removeParticipant(address wallet, address participant) external returns (bool);

    // View functions
    function getWalletInfo(
        address wallet
    ) external view returns (address[] memory participants, uint256[] memory balances);

    function getParticipantBalance(address wallet, address participant) external view returns (uint256);

    function getParticipantWallets(
        address participant
    ) external view returns (address[] memory wallets, uint256[] memory balances);

    function isWalletParticipant(address wallet, address participant) external view returns (bool);
}

/**
 * @title SharedWalletVault
 * @author CloudWalk Inc.
 * @notice A secure vault contract that manages shared wallets and integrates with BRLC token hooks
 */
contract SharedWalletVault is ISharedWallet, AccessControl {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Constants
    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // State variables
    IERC20 private immutable _token;
    mapping(address => SharedWallet) private _wallets;
    mapping(address => EnumerableSet.AddressSet) private _participantWallets;

    constructor(address token_) {
        if (token_ == address(0)) revert SharedWallet_ZeroAddress();
        _token = IERC20(token_);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    // Admin functions
    function createWallet(
        address wallet,
        address[] calldata participants
    ) external onlyRole(ADMIN_ROLE) returns (bool) {
        if (wallet == address(0)) revert SharedWallet_ZeroAddress();
        if (participants.length == 0) revert SharedWallet_EmptyParticipants();
        if (_wallets[wallet].exists) revert SharedWallet_WalletAlreadyExists();

        SharedWallet storage sharedWallet = _wallets[wallet];
        sharedWallet.exists = true;

        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            if (participant == address(0)) revert SharedWallet_ZeroAddress();

            sharedWallet.participants.push(participant);
            sharedWallet.participantInfo[participant].balance = 0;
            _participantWallets[participant].add(wallet);
        }

        emit WalletCreated(wallet, participants);
        return true;
    }

    function addParticipant(address wallet, address participant) external onlyRole(ADMIN_ROLE) returns (bool) {
        if (!_wallets[wallet].exists) revert SharedWallet_WalletNotExists();
        if (participant == address(0)) revert SharedWallet_ZeroAddress();
        if (_wallets[wallet].participantInfo[participant].balance > 0) revert SharedWallet_ParticipantAlreadyExists();

        _wallets[wallet].participants.push(participant);
        _participantWallets[participant].add(wallet);

        emit WalletParticipantAdded(wallet, participant);
        return true;
    }

    function removeParticipant(address wallet, address participant) external onlyRole(ADMIN_ROLE) returns (bool) {
        SharedWallet storage sharedWallet = _wallets[wallet];
        if (!sharedWallet.exists) revert SharedWallet_WalletNotExists();
        if (sharedWallet.participantInfo[participant].balance > 0) revert SharedWallet_ParticipantHasBalance();

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
        emit WalletParticipantRemoved(wallet, participant);
        return true;
    }

    // Hook implementation
    function beforeTokenTransfer(address from, address to, uint256 amount) external override {
        // No pre-transfer validation needed
    }

    function afterTokenTransfer(address from, address to, uint256 amount) external override {
        if (msg.sender != address(_token)) revert SharedWallet_UnauthorizedToken();
        if (amount == 0) return;

        // Handle transfer to wallet
        if (_wallets[to].exists) {
            _handleTransferToWallet(from, to, amount);
        }
            // Handle transfer from wallet
        else if (_wallets[from].exists) {
            _handleTransferFromWallet(from, to, amount);
        }
    }

    // Internal functions
    function _handleTransferToWallet(address from, address wallet, uint256 amount) internal {
        SharedWallet storage sharedWallet = _wallets[wallet];

        // If sender is a participant, update only their balance
        if (isWalletParticipant(wallet, from)) {
            sharedWallet.participantInfo[from].balance += amount;
            sharedWallet.totalBalance += amount;
            emit WalletDeposit(wallet, from, amount);
        }
            // If sender is not a participant, distribute proportionally
        else {
            _distributeProportionally(wallet, amount);
        }
    }

    function _handleTransferFromWallet(address wallet, address to, uint256 amount) internal {
        SharedWallet storage sharedWallet = _wallets[wallet];

        // If recipient is a participant and has sufficient balance, deduct from their balance
        if (isWalletParticipant(wallet, to) && sharedWallet.participantInfo[to].balance >= amount) {
            sharedWallet.participantInfo[to].balance -= amount;
            sharedWallet.totalBalance -= amount;
            emit WalletWithdrawal(wallet, to, amount);
        }
            // Otherwise, deduct proportionally from all participants
        else {
            _deductProportionally(wallet, amount);
        }
    }

    function _distributeProportionally(address wallet, uint256 amount) internal {
        SharedWallet storage sharedWallet = _wallets[wallet];
        uint256 totalBalance = sharedWallet.totalBalance;
        address[] memory participants = sharedWallet.participants;

        // If wallet is empty, distribute equally
        if (totalBalance == 0) {
            uint256 shareAmount = amount / participants.length;
            for (uint256 i = 0; i < participants.length; i++) {
                address participant = participants[i];
                sharedWallet.participantInfo[participant].balance += shareAmount;
            }
            sharedWallet.totalBalance += shareAmount * participants.length;
        }
            // Otherwise distribute proportionally to existing balances
        else {
            for (uint256 i = 0; i < participants.length; i++) {
                address participant = participants[i];
                uint256 participantBalance = sharedWallet.participantInfo[participant].balance;
                if (participantBalance > 0) {
                    uint256 share = (amount * participantBalance) / totalBalance;
                    sharedWallet.participantInfo[participant].balance += share;
                }
            }
            sharedWallet.totalBalance += amount;
        }
    }

    function _deductProportionally(address wallet, uint256 amount) internal {
        SharedWallet storage sharedWallet = _wallets[wallet];
        uint256 totalBalance = sharedWallet.totalBalance;
        address[] memory participants = sharedWallet.participants;

        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            uint256 participantBalance = sharedWallet.participantInfo[participant].balance;
            if (participantBalance > 0) {
                uint256 share = (amount * participantBalance) / totalBalance;
                sharedWallet.participantInfo[participant].balance -= share;
            }
        }
        sharedWallet.totalBalance -= amount;

        emit SharedTransfer(wallet, address(0), address(0), amount);
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

    function getParticipantWallets(
        address participant
    ) external view returns (address[] memory wallets, uint256[] memory balances) {
        wallets = _participantWallets[participant].values();
        balances = new uint256[](wallets.length);

        for (uint256 i = 0; i < wallets.length; i++) {
            balances[i] = _wallets[wallets[i]].participantInfo[participant].balance;
        }
    }

    function isWalletParticipant(address wallet, address participant) public view returns (bool) {
        if (!_wallets[wallet].exists) return false;
        return _participantWallets[participant].contains(wallet);
    }
}