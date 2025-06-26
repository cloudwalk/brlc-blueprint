// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { AccessControlExtUpgradeable } from "./base/AccessControlExtUpgradeable.sol";
import { PausableExtUpgradeable } from "./base/PausableExtUpgradeable.sol";
import { RescuableUpgradeable } from "./base/RescuableUpgradeable.sol";
import { UUPSExtUpgradeable } from "./base/UUPSExtUpgradeable.sol";
import { Versionable } from "./base/Versionable.sol";

import { IERC20Hook } from "./interfaces/IERC20Hook.sol";
import { ISharedWalletController, ISharedWalletControllerPrimary } from "./interfaces/ISharedWalletController.sol";

import { SharedWalletControllerStorageLayout } from "./SharedWalletControllerStorageLayout.sol";

/**
 * @title SharedWalletController contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Manages shared wallets and integrates them with an ERC20 token through hooks.
 */
contract SharedWalletController is
    SharedWalletControllerStorageLayout,
    ISharedWalletController,
    IERC20Hook,
    AccessControlExtUpgradeable,
    PausableExtUpgradeable,
    RescuableUpgradeable,
    UUPSExtUpgradeable,
    Versionable
{
    // ------------------ Types ----------------------------------- //

    using EnumerableSet for EnumerableSet.AddressSet;

    /**
     * @dev Possible types of transfers in a shared wallet for internal use.
     *
     * The values:
     *
     * - Receiving = 0 -- The transfer is incoming to the wallet.
     * - Spending = 1 --- The transfer is outgoing from the wallet.
     */
    enum TransferKind {
        Receiving,
        Spending
    }

    // ------------------ Constructor ----------------------------- //

    /**
     * @dev Constructor that prohibits the initialization of the implementation of the upgradeable contract.
     *
     * See details:
     * https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable#initializing_the_implementation_contract
     *
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    // ------------------ Initializers ---------------------------- //

    /**
     * @dev Initializer of the upgradeable contract.
     *
     * See details: https://docs.openzeppelin.com/upgrades-plugins/writing-upgradeable
     *
     * @param token_ The address of the token to set as the underlying one.
     */
    function initialize(address token_) external initializer {
        if (token_ == address(0)) {
            revert SharedWalletController_WalletAddressZero();
        }

        __AccessControlExt_init_unchained();
        __PausableExt_init_unchained();
        __Rescuable_init_unchained();
        __UUPSExt_init_unchained(); // This is needed only to avoid errors during coverage assessment

        _getSharedWalletControllerStorage().token = token_;

        _setRoleAdmin(ADMIN_ROLE, GRANTOR_ROLE);
        _grantRole(OWNER_ROLE, _msgSender());
    }

    // ------------------ Transactional primary functions --------- //

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     *
     * @dev Requirements:
     *
     * - The caller must have the {ADMIN_ROLE} role.
     * - The provided wallet address must not be zero.
     * - The provided participants array must not be empty.
     */
    function createWallet(
        address wallet,
        address[] calldata participants
    ) external onlyRole(ADMIN_ROLE) {
        if (wallet == address(0)) revert SharedWalletController_WalletAddressZero();
        if (participants.length == 0) revert SharedWalletController_ParticipantArrayEmpty();
        SharedWallet storage sharedWallet = _getSharedWalletControllerStorage().wallets[wallet];
        if (sharedWallet.status != SharedWalletStatus.Nonexistent) {
            revert SharedWalletController_WalletExistentAlready();
        }

        sharedWallet.status = SharedWalletStatus.Active;
        emit WalletCreated(wallet);
        emit WalletStatusChanged(wallet, SharedWalletStatus.Active, SharedWalletStatus.Nonexistent);

        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            _addParticipantToWallet(wallet, participant);
        }
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     *
     * @dev Requirements:
     *
     * - The caller must have the {ADMIN_ROLE} role.
     * - The provided wallet address must not be zero.
     */
    function deactivateWallet(address wallet) external onlyRole(ADMIN_ROLE) {
        SharedWallet storage sharedWallet = _getExistentWallet(wallet);
        if (sharedWallet.status != SharedWalletStatus.Active) {
            revert SharedWalletController_WalletStatusIncompatible(sharedWallet.status, SharedWalletStatus.Active);
        }
        if (sharedWallet.totalBalance > 0) revert SharedWalletController_WalletBalanceNonzero();
        _getSharedWalletControllerStorage().wallets[wallet].status = SharedWalletStatus.Deactivated;
        emit WalletStatusChanged(wallet, SharedWalletStatus.Deactivated, SharedWalletStatus.Active);
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     *
     * @dev Requirements:
     *
     * - The caller must have the {ADMIN_ROLE} role.
     * - The provided wallet address must not be zero.
     */
    function activateWallet(address wallet) external onlyRole(ADMIN_ROLE) {
        SharedWallet storage sharedWallet = _getExistentWallet(wallet);
        if (sharedWallet.status != SharedWalletStatus.Deactivated) {
            revert SharedWalletController_WalletStatusIncompatible(
                sharedWallet.status,
                SharedWalletStatus.Deactivated
            );
        }
        sharedWallet.status = SharedWalletStatus.Active;
        emit WalletStatusChanged(wallet, SharedWalletStatus.Active, SharedWalletStatus.Deactivated);
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     *
     * @dev Requirements:
     *
     * - The caller must have the {OWNER_ROLE} role.
     * - The provided wallet address must not be zero.
     */
    function removeWallet(address wallet) external onlyRole(OWNER_ROLE) {
        SharedWallet storage sharedWallet = _getExistentWallet(wallet);
        if (sharedWallet.totalBalance > 0) revert SharedWalletController_WalletBalanceNonzero();
        for (uint256 i = 0; i < sharedWallet.participants.length; i++) {
            _removeParticipantFromWallet(wallet, sharedWallet.participants[i], false);
        }
        sharedWallet.status = SharedWalletStatus.Nonexistent;
        emit WalletStatusChanged(wallet, SharedWalletStatus.Nonexistent, sharedWallet.status);
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     *
     * @dev Requirements:
     *
     * - The caller must have the {ADMIN_ROLE} role.
     * - The provided wallet address must not be zero.
     * - The provided participants array must not be empty.
     * - The provided participants array must not contain duplicates.
     * - The provided participants array must not contain the zero address.
     * - The provided participants array must not contain the other shared wallet addresses.
     */
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

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     *
     * @dev Requirements:
     *
     * - The caller must have the {ADMIN_ROLE} role.
     * - The provided wallet address must not be zero.
     * - The provided participants array must not be empty.
     * - The provided participants array must not contain duplicates.
     * - The provided participants array must not contain the zero address.
     */
    function removeParticipants(
        address wallet,
        address[] calldata participants
    ) external onlyRole(ADMIN_ROLE) {
        _getExistentWallet(wallet);
        for (uint256 i = 0; i < participants.length; i++) {
            _removeParticipantFromWallet(wallet, participants[i], true);
        }
    }

    // ------------------ Transactional hook functions ------------ //

    /**
     * @inheritdoc IERC20Hook
     *
     * @dev Requirements:
     *
     * - The caller must be the token contract.
     */
    function beforeTokenTransfer(address from, address to, uint256 amount) external {
        // No pre-transfer validation needed
    }

    /**
     * @inheritdoc IERC20Hook
     *
     * @dev Requirements:
     *
     * - The caller must be the token contract.
     */
    function afterTokenTransfer(address from, address to, uint256 amount) external {
        if (msg.sender != address(_getSharedWalletControllerStorage().token)) revert SharedWalletController_TokenUnauthorized();
        if (amount == 0) return;

        SharedWalletStatus status = _getSharedWalletControllerStorage().wallets[from].status;
        if (status == SharedWalletStatus.Active) {
            _handleTransferFromWallet(from, to, amount);
        } else if (status == SharedWalletStatus.Deactivated) {
            revert SharedWalletController_WalletStatusIncompatible(SharedWalletStatus.Deactivated, SharedWalletStatus.Active);
        }

        status = _getSharedWalletControllerStorage().wallets[to].status;
        if (status == SharedWalletStatus.Active) {
            _handleTransferToWallet(from, to, amount);
        } else if (status == SharedWalletStatus.Deactivated) {
            revert SharedWalletController_WalletStatusIncompatible(SharedWalletStatus.Deactivated, SharedWalletStatus.Active);
        }
    }

    // ------------------ View functions -------------------------- //

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     *
     * @dev Requirements:
     *
     * - The provided participantWalletPairs array must not contain pairs with both zero addresses.
     */
    function getParticipantStates(
        WalletParticipantPair[] calldata participantWalletPairs
    ) external view returns (ParticipantStateView[] memory participantStates) {
        WalletParticipantPair[] memory pairs = _normalizeParticipantWalletPairs(participantWalletPairs);
        uint256 pairsCount = pairs.length;
        participantStates = new ParticipantStateView[](pairsCount);
        for (uint256 i = 0; i < pairsCount; i++) {
            address wallet = pairs[i].wallet;
            address participant = pairs[i].participant;
            ParticipantState storage state = _getSharedWalletControllerStorage().wallets[wallet].participantStates[participant];
            participantStates[i].wallet = wallet;
            participantStates[i].participant = participant;
            participantStates[i].status = state.status;
            participantStates[i].index = state.index;
            participantStates[i].balance = state.balance;
        }
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function getParticipantBalance(address wallet, address participant) external view returns (uint256) {
        ParticipantState storage state = _getSharedWalletControllerStorage().wallets[wallet].participantStates[participant];
        if (state.status == ParticipantStatus.Active) {
            return state.balance;
        } else {
            return 0;
        }
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function getWallets(address participant) external view returns (address[] memory wallets) {
        return _getSharedWalletControllerStorage().participantWallets[participant].values();
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function getParticipants(address wallet) external view returns (address[] memory participants) {
        return _getSharedWalletControllerStorage().wallets[wallet].participants;
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function isParticipant(address wallet, address participant) external view returns (bool) {
        return _getSharedWalletControllerStorage().wallets[wallet].participantStates[participant].status == ParticipantStatus.Active;
    }

    // ------------------ Pure functions -------------------------- //

    /// @inheritdoc ISharedWalletController
    function proveSharedWalletController() external pure {}

    // ------------------ Internal functions ---------------------- //

    /**
     * @dev Adds a participant to a wallet.
     * @param wallet The address of the wallet.
     * @param participant The address of the participant.
     */
    function _addParticipantToWallet(
        address wallet,
        address participant
    ) internal {
        if (participant == address(0)) revert SharedWalletController_ParticipantAddressZero();
        SharedWallet storage sharedWallet = _getSharedWalletControllerStorage().wallets[wallet];
        if (sharedWallet.participantStates[participant].status != ParticipantStatus.Nonexistent) {
            revert SharedWalletController_ParticipantExistentAlready();
        }
        if(_getSharedWalletControllerStorage().wallets[participant].status != SharedWalletStatus.Nonexistent) {
            revert SharedWalletController_ParticipantIsSharedWallet();
        }
        if (sharedWallet.participants.length >= _getMaxParticipantsPerWallet()) {
            revert SharedWalletController_ParticipantCountExcess();
        }

        uint256 participantIndex = sharedWallet.participants.length;
        sharedWallet.participants.push(participant);
        ParticipantState storage state = sharedWallet.participantStates[participant];
        state.status = ParticipantStatus.Active;
        state.index = uint16(participantIndex);
        state.balance = 0;
        _getSharedWalletControllerStorage().participantWallets[participant].add(wallet);

        emit WalletParticipantOperation(
            wallet,
            participant,
            ParticipantOperationKind.Addition
        );
    }

    /**
     * @dev Removes a participant from a wallet.
     * @param wallet The address of the wallet.
     * @param participant The address of the participant.
     */
    function _removeParticipantFromWallet(
        address wallet,
        address participant,
        bool prohibitInitiatorRemoval
    ) internal {
        SharedWallet storage sharedWallet = _getSharedWalletControllerStorage().wallets[wallet];
        if (sharedWallet.participantStates[participant].status == ParticipantStatus.Nonexistent) {
            revert SharedWalletController_ParticipantNonexistent(participant);
        }
        if (sharedWallet.participantStates[participant].balance > 0) {
            revert SharedWalletController_ParticipantBalanceNonzero(participant);
        }
        if (prohibitInitiatorRemoval && sharedWallet.participantStates[participant].index == 0) {
            revert SharedWalletController_ParticipantUnremovable(participant);
        }

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

        _getSharedWalletControllerStorage().participantWallets[participant].remove(wallet);

        emit WalletParticipantOperation(
            wallet,
            participant,
            ParticipantOperationKind.Removal
        );

    }

    /**
     * @dev Returns the maximum number of participants per wallet.
     * 
     * This function is useful for testing purposes.
     * 
     * @return The maximum number of participants per wallet.
     */
    function _getMaxParticipantsPerWallet() internal pure virtual returns (uint256) {
        return MAX_PARTICIPANTS_PER_WALLET;
    }

    /**
     * @dev Returns a shared wallet by its address after ensuring it exists.
     * @param wallet The address of the wallet.
     * @return The shared wallet as a storage reference.
     */
    function _getExistentWallet(address wallet) internal view returns (SharedWallet storage) {
        SharedWallet storage sharedWallet = _getSharedWalletControllerStorage().wallets[wallet];
        if (sharedWallet.status == SharedWalletStatus.Nonexistent) revert SharedWalletController_WalletNonexistent();
        return sharedWallet;
    }

    /**
     * @dev Handles a transfer from a wallet.
     * @param wallet The address of the wallet.
     * @param to The address of the recipient.
     * @param amount The amount of the transfer.
     */
    function _handleTransferFromWallet(address wallet, address to, uint256 amount) internal {
        if (_getSharedWalletControllerStorage().wallets[wallet].participantStates[to].status == ParticipantStatus.Active) {
            _processFunding(wallet, to, amount, uint256(TransferKind.Spending));
        } else {
            _processTransfer(wallet, amount, uint256(TransferKind.Spending));
        }
    }

    /**
     * @dev Handles a transfer to a wallet.
     * @param from The address of the sender.
     * @param wallet The address of the wallet.
     * @param amount The amount of the transfer.
     */
    function _handleTransferToWallet(address from, address wallet, uint256 amount) internal {
        if (_getSharedWalletControllerStorage().wallets[wallet].participantStates[from].status == ParticipantStatus.Active) {
            _processFunding(wallet, from, amount, uint256(TransferKind.Receiving));
        } else {
            _processTransfer(wallet, amount, uint256(TransferKind.Receiving));
        }
    }

    /**
     * @dev Processes a funding operation.
     * @param wallet The address of the wallet.
     * @param participant The address of the participant.
     * @param amount The amount of the operation.
     * @param transferKind The kind of transfer according to the {TransferKind} enum.
     */
    function _processFunding(
        address wallet,
        address participant,
        uint256 amount,
        uint256 transferKind
    ) internal {
        SharedWallet storage sharedWallet = _getSharedWalletControllerStorage().wallets[wallet];
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
                revert SharedWalletController_WalletBalanceInsufficient();
            }
            if (oldParticipantBalance < amount) {
                revert SharedWalletController_ParticipantBalanceInsufficient();
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

    /**
     * @dev Processes a transfer operation.
     * @param wallet The address of the wallet.
     * @param amount The amount of the operation.
     * @param transferKind The kind of transfer according to the {TransferKind} enum.
     */
    function _processTransfer(address wallet, uint256 amount, uint256 transferKind) internal {
        SharedWallet storage sharedWallet = _getSharedWalletControllerStorage().wallets[wallet];
        uint256 oldWalletBalance = sharedWallet.totalBalance;
        uint256 newWalletBalance;
        if (transferKind == uint256(TransferKind.Receiving)) {
            newWalletBalance = oldWalletBalance + amount;
        } else {
            if (oldWalletBalance < amount) {
                revert SharedWalletController_WalletBalanceInsufficient();
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

    /**
     * @dev Determines the shares of the participants in the transfer.
     * @param amount The amount of the transfer.
     * @param sharedWallet The shared wallet as a storage reference.
     * @return The shares of the participants.
     */
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

    /**
     * @dev Calculates a share of a participant in a transfer.
     * @param amount The amount of the transfer.
     * @param balance The balance of the participant.
     * @param totalBalance The total balance of the shared wallet.
     * @return The share of the participant.
     */
    function _calculateShare(
        uint256 amount,
        uint256 balance,
        uint256 totalBalance
    ) internal pure returns (uint256) {
        return amount * balance / totalBalance; // TODO: Round to cents
    }

    /**
     * @dev Normalizes the participant-wallet pairs by expanding zero addresses to participants or wallets.
     * @param participantWalletPairs The participant-wallet pairs to normalize.
     * @return The normalized participant-wallet pairs.
     */
    function _normalizeParticipantWalletPairs(
        WalletParticipantPair[] calldata participantWalletPairs
    ) internal view returns (WalletParticipantPair[] memory) {
        uint256 initialPairCount = participantWalletPairs.length;

        // First pass: count actual pairs and validate
        uint256 actualPairCount = 0;
        for (uint256 i = 0; i < initialPairCount; i++) {
            WalletParticipantPair calldata pair = participantWalletPairs[i];

            if (pair.wallet == address(0) && pair.participant == address(0)) {
                revert SharedWalletController_ParticipantAddressZero();
            }

            if (pair.wallet == address(0)) {
                actualPairCount += _getSharedWalletControllerStorage().participantWallets[pair.participant].length();
            } else if (pair.participant == address(0)) {
                actualPairCount += _getSharedWalletControllerStorage().wallets[pair.wallet].participants.length;
            } else {
                actualPairCount += 1;
            }
        }

        if (actualPairCount == initialPairCount) {
            return participantWalletPairs;
        }

        // Second pass: build the expanded array
        WalletParticipantPair[] memory actualPairs = new WalletParticipantPair[](actualPairCount);
        uint256 pairIndex = 0;

        for (uint256 i = 0; i < initialPairCount; i++) {
            WalletParticipantPair calldata pair = participantWalletPairs[i];

            if (pair.wallet == address(0)) {
                EnumerableSet.AddressSet storage participantWallets = _getSharedWalletControllerStorage().participantWallets[pair.participant];
                uint256 walletsCount = participantWallets.length();
                for (uint256 j = 0; j < walletsCount; j++) {
                    actualPairs[pairIndex++] = WalletParticipantPair(participantWallets.at(j), pair.participant);
                }
            } else if (pair.participant == address(0)) {
                SharedWallet storage sharedWallet = _getSharedWalletControllerStorage().wallets[pair.wallet];
                uint256 participantsCount = sharedWallet.participants.length;
                for (uint256 j = 0; j < participantsCount; j++) {
                    actualPairs[pairIndex++] = WalletParticipantPair(pair.wallet, sharedWallet.participants[j]);
                }
            } else {
                actualPairs[pairIndex++] = pair;
            }
        }

        return actualPairs;
    }

    /**
     * @dev The upgrade validation function for the UUPSExtUpgradeable contract.
     * @param newImplementation The address of the new implementation.
     */
    function _validateUpgrade(address newImplementation) internal view override onlyRole(OWNER_ROLE) {
        try ISharedWalletController(newImplementation).proveSharedWalletController() {} catch {
            revert SharedWalletController_ImplementationAddressInvalid();
        }
    }
}
