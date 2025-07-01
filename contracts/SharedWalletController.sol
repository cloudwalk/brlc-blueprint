// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

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
    using SafeCast for uint256;

    /**
     * @dev Possible directions of transfers in a shared wallet for internal use.
     *
     * The values:
     *
     * - In = 0 --- The transfer is incoming to the wallet.
     * - Out = 1 -- The transfer is outgoing from the wallet.
     */
    enum TransferDirection {
        In,
        Out
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
        if (wallet == address(0)) {
            revert SharedWalletController_WalletAddressZero();
        }
        if (participants.length == 0) {
            revert SharedWalletController_ParticipantArrayEmpty();
        }

        WalletState storage walletState = _getSharedWalletControllerStorage().walletStates[wallet];

        if (walletState.status != WalletStatus.Nonexistent) {
            revert SharedWalletController_WalletExistentAlready();
        }

        walletState.status = WalletStatus.Active;
        _incrementWalletCount();
        emit WalletCreated(wallet);

        uint256 participantsCount = participants.length;
        for (uint256 i = 0; i < participantsCount; i++) {
            _addParticipant(wallet, participants[i]);
        }
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     *
     * @dev Requirements:
     *
     * - The caller must have the {ADMIN_ROLE} role.
     * - The provided wallet address must not be zero.
     * - The provided wallet must be active.
     * - The wallet must have the zero balance.
     */
    function suspendWallet(address wallet) external onlyRole(ADMIN_ROLE) {
        WalletState storage walletState = _getExistentWallet(wallet);

        if (walletState.status != WalletStatus.Active) {
            revert SharedWalletController_WalletStatusIncompatible(walletState.status, WalletStatus.Active);
        }
        if (walletState.balance > 0) {
            revert SharedWalletController_WalletBalanceNonzero();
        }

        walletState.status = WalletStatus.Suspended;
        emit WalletSuspended(wallet);
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     *
     * @dev Requirements:
     *
     * - The caller must have the {ADMIN_ROLE} role.
     * - The provided wallet address must not be zero.
     * - The wallet must be suspended.
     */
    function resumeWallet(address wallet) external onlyRole(ADMIN_ROLE) {
        WalletState storage walletState = _getExistentWallet(wallet);
        if (walletState.status != WalletStatus.Suspended) {
            revert SharedWalletController_WalletStatusIncompatible(walletState.status, WalletStatus.Suspended);
        }
        if (walletState.participants.length == 0) {
            revert SharedWalletController_WalletParticipantCountZero();
        }
        walletState.status = WalletStatus.Active;
        emit WalletResumed(wallet);
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     *
     * @dev Requirements:
     *
     * - The caller must have the {OWNER_ROLE} role.
     * - The provided wallet address must not be zero.
     * - The provided wallet must be suspended.
     */
    function deleteWallet(address wallet) external onlyRole(OWNER_ROLE) {
        WalletState storage walletState = _getExistentWallet(wallet);
        if (walletState.status != WalletStatus.Suspended) {
            revert SharedWalletController_WalletStatusIncompatible(walletState.status, WalletStatus.Suspended);
        }
        uint256 participantsCount = walletState.participants.length;
        for (uint256 i = 0; i < participantsCount; i++) {
            _removeParticipant(wallet, walletState.participants[i], walletState);
        }
        walletState.status = WalletStatus.Nonexistent;
        emit WalletDeleted(wallet);
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
        uint256 participantsCount = participants.length;
        for (uint256 i = 0; i < participantsCount; i++) {
            address participant = participants[i];
            _addParticipant(wallet, participant);
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
        WalletState storage walletState = _getExistentWallet(wallet);

        uint256 participantsCount = participants.length;
        for (uint256 i = 0; i < participantsCount; i++) {
            _removeParticipant(wallet, participants[i], walletState);
        }

        if (walletState.status == WalletStatus.Active &&
            walletState.participants.length == 0) {
            revert SharedWalletController_WalletWouldBecomeEmpty();
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
        if (_msgSender() != address(_getSharedWalletControllerStorage().token)) {
            revert SharedWalletController_TokenUnauthorized();
        }
        if (amount == 0) return;

        WalletStatus status = _getSharedWalletControllerStorage().walletStates[from].status;
        if (status == WalletStatus.Active) {
            _handleOutgoingTransfer(from, to, amount);
        } else if (status == WalletStatus.Suspended) {
            revert SharedWalletController_WalletStatusIncompatible(status, WalletStatus.Active);
        }

        status = _getSharedWalletControllerStorage().walletStates[to].status;
        if (status == WalletStatus.Active) {
            _handleIncomingTransfer(from, to, amount);
        } else if (status == WalletStatus.Suspended) {
            revert SharedWalletController_WalletStatusIncompatible(status, WalletStatus.Active);
        }
    }

    // ------------------ View functions -------------------------- //

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function isParticipant(address wallet, address participant) external view returns (bool) {
        return _getSharedWalletControllerStorage().walletStates[wallet].participantStates[participant].status == ParticipantStatus.Registered;
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function getParticipantBalance(address wallet, address participant) external view returns (uint256) {
        return _getSharedWalletControllerStorage().walletStates[wallet].participantStates[participant].balance;
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function getParticipantWallets(address participant) external view returns (address[] memory wallets) {
        return _getSharedWalletControllerStorage().participantWallets[participant].values();
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function getParticipantOverviews(address[] calldata participants) external view returns (ParticipantOverview[] memory overviews) {
        uint256 participantsCount = participants.length;
        overviews = new ParticipantOverview[](participantsCount);

        for (uint256 i = 0; i < participantsCount; i++) {
            address participant = participants[i];
            EnumerableSet.AddressSet storage participantWallets =
                _getSharedWalletControllerStorage().participantWallets[participant];

            uint256 walletsCount = participantWallets.length();
            WalletSummary[] memory walletSummaries = new WalletSummary[](walletsCount);
            uint256 totalBalance = 0;

            for (uint256 j = 0; j < walletsCount; j++) {
                address wallet = participantWallets.at(j);
                WalletState storage walletState = _getSharedWalletControllerStorage().walletStates[wallet];
                ParticipantState storage participantState = walletState.participantStates[participant];

                uint256 participantBalance = participantState.balance;
                totalBalance += participantBalance;

                walletSummaries[j] = WalletSummary({
                    wallet: wallet,
                    walletStatus: walletState.status,
                    walletBalance: walletState.balance,
                    participantStatus: participantState.status,
                    participantBalance: participantBalance
                });
            }

            overviews[i] = ParticipantOverview({
                participant: participant,
                totalBalance: totalBalance,
                walletSummaries: walletSummaries
            });
        }
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function getWalletParticipants(address wallet) external view returns (address[] memory participants) {
        return _getSharedWalletControllerStorage().walletStates[wallet].participants;
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function getWalletOverviews(address[] calldata wallets) external view returns (WalletOverview[] memory overviews) {
        uint256 walletsCount = wallets.length;
        overviews = new WalletOverview[](walletsCount);

        for (uint256 i = 0; i < walletsCount; i++) {
            address walletAddress = wallets[i];
            WalletState storage walletState = _getSharedWalletControllerStorage().walletStates[walletAddress];

            // Build participant summaries array
            uint256 participantsCount = walletState.participants.length;
            ParticipantSummary[] memory participantSummaries = new ParticipantSummary[](participantsCount);

            for (uint256 j = 0; j < participantsCount; j++) {
                address participantAddress = walletState.participants[j];
                ParticipantState storage participantState = walletState.participantStates[participantAddress];

                participantSummaries[j] = ParticipantSummary({
                    participant: participantAddress,
                    participantStatus: participantState.status,
                    participantBalance: participantState.balance
                });
            }

            overviews[i] = WalletOverview({
                wallet: walletAddress,
                walletStatus: walletState.status,
                walletBalance: walletState.balance,
                participantSummaries: participantSummaries
            });
        }
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function getWalletCount() external view returns (uint256) {
        return _getSharedWalletControllerStorage().walletCount;
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     *
     * @dev Requirements:
     *
     * - Both wallet and participant addresses cannot be zero in the same pair.
     */
    function getRelationshipOverviews(
        WalletParticipantPair[] calldata pairs
    ) external view returns (WalletParticipantOverview[] memory overviews) {
        WalletParticipantPair[] memory normalizedPairs = _normalizeWalletParticipantPairs(pairs);
        uint256 count = normalizedPairs.length;
        overviews = new WalletParticipantOverview[](count);
        for (uint256 i = 0; i < count; i++) {
            address wallet = normalizedPairs[i].wallet;
            address participant = normalizedPairs[i].participant;
            WalletState storage walletState = _getSharedWalletControllerStorage().walletStates[wallet];
            ParticipantState storage participantState = walletState.participantStates[participant];

            overviews[i] = WalletParticipantOverview({
                // Wallet information
                wallet: wallet,
                    walletStatus: walletState.status,
                walletBalance: walletState.balance,
                // Participant information
                participant: participant,
                    participantStatus: participantState.status,
                    participantBalance: participantState.balance
            });
        }
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function getCombinedWalletsBalance() external view returns (uint256) {
        return _getSharedWalletControllerStorage().combinedWalletsBalance;
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
    function _addParticipant(
        address wallet,
        address participant
    ) internal {
        if (participant == address(0)) revert SharedWalletController_ParticipantAddressZero();
        WalletState storage walletState = _getSharedWalletControllerStorage().walletStates[wallet];
        ParticipantState storage participantState = walletState.participantStates[participant];
        if (participantState.status != ParticipantStatus.NonRegistered) {
            revert SharedWalletController_ParticipantRegisteredAlready();
        }
        if (_getSharedWalletControllerStorage().walletStates[participant].status != WalletStatus.Nonexistent) {
            revert SharedWalletController_ParticipantIsSharedWallet();
        }
        if (walletState.participants.length >= _getMaxParticipantsPerWallet()) {
            revert SharedWalletController_ParticipantCountExcess();
        }

        uint256 newParticipantIndex = walletState.participants.length;
        walletState.participants.push(participant);

        participantState.status = ParticipantStatus.Registered;
        participantState.index = uint16(newParticipantIndex);
        participantState.balance = 0;

        _getSharedWalletControllerStorage().participantWallets[participant].add(wallet);

        emit ParticipantAdded(wallet, participant);
    }

    /**
     * @dev Removes a participant from a wallet.
     * @param wallet The address of the wallet.
     * @param participant The address of the participant.
     * @param walletState The shared wallet storage reference.
     */
    function _removeParticipant(
        address wallet,
        address participant,
        WalletState storage walletState
    ) internal {
        if (walletState.participantStates[participant].status == ParticipantStatus.NonRegistered) {
            revert SharedWalletController_ParticipantNonRegistered(participant);
        }
        if (walletState.participantStates[participant].balance > 0) {
            revert SharedWalletController_ParticipantBalanceNonzero(participant);
        }

        _removeParticipantFromWallet(participant, walletState);
        _removeWalletFromParticipant(wallet, participant);

        emit ParticipantRemoved(wallet, participant);
    }

    /**
     * @dev Removes a participant from the wallet's data structures.
     * @param walletState The shared wallet storage reference.
     * @param participant The address of the participant to remove.
     */
    function _removeParticipantFromWallet(
        address participant,
        WalletState storage walletState
    ) internal {
        // Remove from the array and clear storage
        uint256 removedIndex = walletState.participantStates[participant].index;
        uint256 lastIndex = walletState.participants.length - 1;
        address participantWithLastIndex = walletState.participants[lastIndex];

        walletState.participants[removedIndex] = walletState.participants[lastIndex];
        walletState.participantStates[participantWithLastIndex].index = uint16(removedIndex);

        delete walletState.participants[lastIndex];
        walletState.participants.pop();
        delete walletState.participantStates[participant];
        }

    /**
     * @dev Removes a wallet from the participant's wallet list.
     * @param participant The address of the participant.
     * @param wallet The address of the wallet to remove.
     */
    function _removeWalletFromParticipant(address wallet, address participant) internal {
        _getSharedWalletControllerStorage().participantWallets[participant].remove(wallet);
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
    function _getExistentWallet(address wallet) internal view returns (WalletState storage) {
        WalletState storage walletState = _getSharedWalletControllerStorage().walletStates[wallet];
        if (walletState.status == WalletStatus.Nonexistent) {
            revert SharedWalletController_WalletNonexistent();
        }
        return walletState;
    }

    /**
     * @dev Handles an outgoing transfer from a wallet.
     * @param wallet The address of the wallet.
     * @param to The address of the recipient.
     * @param amount The amount of the transfer.
     */
    function _handleOutgoingTransfer(address wallet, address to, uint256 amount) internal {
        WalletState storage walletState = _getSharedWalletControllerStorage().walletStates[wallet];
        if (walletState.participantStates[to].status == ParticipantStatus.Registered) {
            _processDirectTransfer(wallet, to, amount, uint256(TransferDirection.Out));
        } else {
            _processDistributionTransfer(wallet, amount, uint256(TransferDirection.Out));
        }
    }

    /**
     * @dev Handles an incoming transfer to a wallet.
     * @param from The address of the sender.
     * @param wallet The address of the wallet.
     * @param amount The amount of the transfer.
     */
    function _handleIncomingTransfer(address from, address wallet, uint256 amount) internal {
        WalletState storage walletState = _getSharedWalletControllerStorage().walletStates[wallet];
        if (walletState.participantStates[from].status == ParticipantStatus.Registered) {
            _processDirectTransfer(wallet, from, amount, uint256(TransferDirection.In));
        } else {
            _processDistributionTransfer(wallet, amount, uint256(TransferDirection.In));
        }
    }

    /**
     * @dev Processes a direct transfer operation between a participant and the wallet.
     * @param wallet The address of the wallet.
     * @param participant The address of the participant.
     * @param amount The amount of the operation.
     * @param transferDirection The direction of transfer according to the {TransferDirection} enum.
     */
    function _processDirectTransfer(
        address wallet,
        address participant,
        uint256 amount,
        uint256 transferDirection
    ) internal {
        WalletState storage walletState = _getSharedWalletControllerStorage().walletStates[wallet];
        ParticipantState storage participantState = walletState.participantStates[participant];
        uint256 oldWalletBalance = walletState.balance;
        uint256 newWalletBalance;
        uint256 oldParticipantBalance = participantState.balance;
        uint256 newParticipantBalance;

        if (transferDirection == uint256(TransferDirection.In)) {
            newParticipantBalance = oldParticipantBalance + amount;
            newWalletBalance = oldWalletBalance + amount;
            _increaseCombinedWalletsBalance(amount);

            emit Deposit(
                wallet,
                participant,
                newParticipantBalance,
                oldParticipantBalance,
                newWalletBalance,
                oldWalletBalance
            );
        } else {
            if (oldParticipantBalance < amount) {
                revert SharedWalletController_ParticipantBalanceInsufficient();
            }
            unchecked {
                newParticipantBalance = oldParticipantBalance - amount;
                newWalletBalance = oldWalletBalance - amount;
                _getSharedWalletControllerStorage().combinedWalletsBalance -= uint64(amount);
            }

            emit Withdrawal(
                wallet,
                participant,
                newParticipantBalance,
                oldParticipantBalance,
                newWalletBalance,
                oldWalletBalance
            );
        }

        participantState.balance = newParticipantBalance.toUint64();
        walletState.balance = newWalletBalance.toUint64();
    }

    /**
     * @dev Processes a distribution transfer among participants in a wallet.
     * @param wallet The address of the wallet.
     * @param amount The amount of tokens to distribute.
     * @param transferDirection The direction of transfer according to the {TransferDirection} enum.
     */
    function _processDistributionTransfer(address wallet, uint256 amount, uint256 transferDirection) internal {
        WalletState storage walletState = _getSharedWalletControllerStorage().walletStates[wallet];
        uint256 oldWalletBalance = walletState.balance;
        uint256 newWalletBalance;
        if (transferDirection == uint256(TransferDirection.In)) {
            newWalletBalance = oldWalletBalance + amount;
            _increaseCombinedWalletsBalance(amount);
        } else {
            if (oldWalletBalance < amount) {
                revert SharedWalletController_WalletBalanceInsufficient();
            }
            unchecked {
                newWalletBalance = oldWalletBalance - amount;
                _getSharedWalletControllerStorage().combinedWalletsBalance -= uint64(amount);
            }
        }
        walletState.balance = newWalletBalance.toUint64();

        uint256[] memory shares = _calculateParticipantShares(amount, walletState);
        uint256 participantCount = walletState.participants.length;

        for (uint256 i = 0; i < participantCount; ++i) {
            if (shares[i] > 0) {
                address participant = walletState.participants[i];
                ParticipantState storage participantState = walletState.participantStates[participant];
                uint256 oldParticipantBalance = participantState.balance;
                uint256 newParticipantBalance;

                if (transferDirection == uint256(TransferDirection.In)) {
                    newParticipantBalance = oldParticipantBalance + shares[i];

                    emit TransferIn(
                        wallet,
                        participant,
                        newParticipantBalance,
                        oldParticipantBalance,
                        newWalletBalance,
                        oldWalletBalance
                    );
                } else {
                    if (oldParticipantBalance < shares[i]) {
                        revert SharedWalletController_SharesCalculationIncorrect();
                    }
                    unchecked{
                        newParticipantBalance = oldParticipantBalance - shares[i];
                    }

                    emit TransferOut(
                        wallet,
                        participant,
                        newParticipantBalance,
                        oldParticipantBalance,
                        newWalletBalance,
                        oldWalletBalance
                    );
                }

                participantState.balance = newParticipantBalance.toUint64();
            }
        }
    }

    /**
     * @dev Increases the number of existing shared wallets by 1.
     */
    function _incrementWalletCount() internal {
        uint256 newWalletCount = _getSharedWalletControllerStorage().walletCount + 1;
        if (newWalletCount > type(uint32).max) {
            revert SharedWalletController_WalletCountExcess();
        }
        _getSharedWalletControllerStorage().walletCount = uint32(newWalletCount);
    }

    /**
     * @dev Increases the combined wallets balance across all shared wallets by the given amount.
     * @param amount The amount to increase the combined balance by.
     */
    function _increaseCombinedWalletsBalance(uint256 amount) internal {
        uint256 newCombinedBalance = uint256(_getSharedWalletControllerStorage().combinedWalletsBalance) + amount;
        if (newCombinedBalance > type(uint64).max) {
            revert SharedWalletController_CombinedWalletsBalanceExcess();
        }
        _getSharedWalletControllerStorage().combinedWalletsBalance = uint64(newCombinedBalance);
    }

    /**
     * @dev Calculates the shares of the participants in the transfer.
     * @param amount The amount of the transfer.
     * @param walletState The shared wallet as a storage reference.
     * @return The shares of the participants.
     */
    function _calculateParticipantShares(
        uint256 amount,
        WalletState storage walletState
    ) internal view returns (uint256[] memory) {
        uint256 i = walletState.participants.length;
        uint256[] memory shares = new uint256[](i);
        uint256 totalBalance = walletState.balance;
        uint256 totalShares = 0;
        uint256 lastNonZeroBalanceIndex = 0;
        if (totalBalance != 0) {
            do {
                --i;
                uint256 participantBalance = walletState.participantStates[walletState.participants[i]].balance;
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
        uint256 share = amount * balance / totalBalance;
        return (share / ACCURACY_FACTOR) * ACCURACY_FACTOR; // Round down according to the accuracy factor
    }

    /**
     * @dev Normalizes the wallet-participant pairs by expanding zero addresses to participants or wallets.
     * @param pairs The wallet-participant pairs to normalize.
     * @return The normalized wallet-participant pairs.
     */
    function _normalizeWalletParticipantPairs(
        WalletParticipantPair[] calldata pairs
    ) internal view returns (WalletParticipantPair[] memory) {
        uint256 initialPairCount = pairs.length;

        // First pass: count actual pairs and validate
        uint256 actualPairCount = 0;
        for (uint256 i = 0; i < initialPairCount; i++) {
            WalletParticipantPair calldata pair = pairs[i];

            if (pair.wallet == address(0) && pair.participant == address(0)) {
                revert SharedWalletController_WalletParticipantAddressesBothZero();
            }

            if (pair.wallet == address(0)) {
                actualPairCount += _getSharedWalletControllerStorage().participantWallets[pair.participant].length();
            } else if (pair.participant == address(0)) {
                actualPairCount += _getSharedWalletControllerStorage().walletStates[pair.wallet].participants.length;
            } else {
                actualPairCount += 1;
            }
        }

        if (actualPairCount == initialPairCount) {
            return pairs;
        }

        // Second pass: build the expanded array
        WalletParticipantPair[] memory actualPairs = new WalletParticipantPair[](actualPairCount);
        uint256 pairIndex = 0;

        for (uint256 i = 0; i < initialPairCount; i++) {
            WalletParticipantPair calldata pair = pairs[i];

            if (pair.wallet == address(0)) {
                EnumerableSet.AddressSet storage participantWallets =
                    _getSharedWalletControllerStorage().participantWallets[pair.participant];
                uint256 walletsCount = participantWallets.length();
                for (uint256 j = 0; j < walletsCount; j++) {
                    actualPairs[pairIndex++] = WalletParticipantPair(participantWallets.at(j), pair.participant);
                }
            } else if (pair.participant == address(0)) {
                WalletState storage walletState = _getSharedWalletControllerStorage().walletStates[pair.wallet];
                uint256 participantsCount = walletState.participants.length;
                for (uint256 j = 0; j < participantsCount; j++) {
                    actualPairs[pairIndex++] = WalletParticipantPair(pair.wallet, walletState.participants[j]);
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
