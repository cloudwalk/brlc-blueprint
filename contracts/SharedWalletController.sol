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
     * @dev Possible directions of transfers in a shared wallet (for internal use).
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
            revert SharedWalletController_TokenAddressZero();
        }

        __AccessControlExt_init_unchained();
        __PausableExt_init_unchained();
        __Rescuable_init_unchained();
        __UUPSExt_init_unchained(); // Required to avoid errors during test coverage assessment

        SharedWalletControllerStorage storage $ = _getStorage();
        $.token = token_;

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
    function createWallet(address wallet, address[] calldata participants) external onlyRole(ADMIN_ROLE) {
        if (wallet == address(0)) {
            revert SharedWalletController_WalletAddressZero();
        }
        if (participants.length == 0) {
            revert SharedWalletController_ParticipantArrayEmpty();
        }

        SharedWalletControllerStorage storage $ = _getStorage();
        WalletState storage walletState = $.walletStates[wallet];

        if (walletState.status != WalletStatus.Nonexistent) {
            revert SharedWalletController_WalletAlreadyExists();
        }

        walletState.status = WalletStatus.Active;
        _safeIncrementWalletCount($);
        emit WalletCreated(wallet);

        uint256 participantCount = participants.length;
        for (uint256 i = 0; i < participantCount; i++) {
            _addParticipant(wallet, participants[i], walletState, $);
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
        SharedWalletControllerStorage storage $ = _getStorage();
        WalletState storage walletState = _getExistentWallet(wallet, $);

        if (walletState.status != WalletStatus.Active) {
            revert SharedWalletController_WalletStatusIncompatible(walletState.status, WalletStatus.Active);
        }
        if (walletState.balance > 0) {
            revert SharedWalletController_WalletBalanceNotZero();
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
        SharedWalletControllerStorage storage $ = _getStorage();
        WalletState storage walletState = _getExistentWallet(wallet, $);

        if (walletState.status != WalletStatus.Suspended) {
            revert SharedWalletController_WalletStatusIncompatible(walletState.status, WalletStatus.Suspended);
        }
        if (walletState.participants.length == 0) {
            revert SharedWalletController_WalletHasNoParticipants();
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
        SharedWalletControllerStorage storage $ = _getStorage();
        WalletState storage walletState = _getExistentWallet(wallet, $);

        if (walletState.status != WalletStatus.Suspended) {
            revert SharedWalletController_WalletStatusIncompatible(walletState.status, WalletStatus.Suspended);
        }

        uint256 participantCount = walletState.participants.length;
        for (uint256 i = 0; i < participantCount; i++) {
            _removeParticipant(wallet, walletState.participants[i], walletState, $);
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
    function addParticipants(address wallet, address[] calldata participants) external onlyRole(ADMIN_ROLE) {
        SharedWalletControllerStorage storage $ = _getStorage();
        WalletState storage walletState = _getExistentWallet(wallet, $);

        uint256 participantCount = participants.length;
        for (uint256 i = 0; i < participantCount; i++) {
            _addParticipant(wallet, participants[i], walletState, $);
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
    function removeParticipants(address wallet, address[] calldata participants) external onlyRole(ADMIN_ROLE) {
        SharedWalletControllerStorage storage $ = _getStorage();
        WalletState storage walletState = _getExistentWallet(wallet, $);

        uint256 participantCount = participants.length;
        for (uint256 i = 0; i < participantCount; i++) {
            _removeParticipant(wallet, participants[i], walletState, $);
        }

        if (walletState.status == WalletStatus.Active && walletState.participants.length == 0) {
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
     * @dev Called by the ERC20 token contract after each transfer to update shared wallet states.
     * Handles both participant-to-wallet transfers and external-to-wallet transfers with distribution.
     *
     * Requirements:
     *
     * - The caller must be the token contract.
     */
    function afterTokenTransfer(address from, address to, uint256 amount) external {
        SharedWalletControllerStorage storage $ = _getStorage();

        if (_msgSender() != address($.token)) {
            revert SharedWalletController_TokenUnauthorized();
        }
        if (amount == 0) {
            return;
        }

        WalletState storage fromWalletState = $.walletStates[from];
        WalletStatus fromStatus = fromWalletState.status;

        if (fromStatus == WalletStatus.Active) {
            _handleOutgoingTransfer(from, to, amount, fromWalletState, $);
        } else if (fromStatus == WalletStatus.Suspended) {
            revert SharedWalletController_WalletStatusIncompatible(fromStatus, WalletStatus.Active);
        }

        WalletState storage toWalletState = $.walletStates[to];
        WalletStatus toStatus = toWalletState.status;

        if (toStatus == WalletStatus.Active) {
            _handleIncomingTransfer(from, to, amount, toWalletState, $);
        } else if (toStatus == WalletStatus.Suspended) {
            revert SharedWalletController_WalletStatusIncompatible(toStatus, WalletStatus.Active);
        }
    }

    // ------------------ View functions -------------------------- //

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function isParticipant(address wallet, address participant) external view returns (bool) {
        SharedWalletControllerStorage storage $ = _getStorage();
        return $.walletStates[wallet].participantStates[participant].status == ParticipantStatus.Registered;
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function getParticipantBalance(address wallet, address participant) external view returns (uint256) {
        SharedWalletControllerStorage storage $ = _getStorage();
        return $.walletStates[wallet].participantStates[participant].balance;
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function getParticipantWallets(address participant) external view returns (address[] memory wallets) {
        SharedWalletControllerStorage storage $ = _getStorage();
        return $.participantWallets[participant].values();
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function getParticipantOverviews(
        address[] calldata participants
    ) external view returns (ParticipantOverview[] memory overviews) {
        SharedWalletControllerStorage storage $ = _getStorage();

        uint256 participantCount = participants.length;
        overviews = new ParticipantOverview[](participantCount);

        for (uint256 i = 0; i < participantCount; i++) {
            address participant = participants[i];
            EnumerableSet.AddressSet storage participantWallets = $.participantWallets[participant];

            uint256 walletCount = participantWallets.length();
            WalletSummary[] memory walletSummaries = new WalletSummary[](walletCount);
            uint256 totalBalance = 0;

            for (uint256 j = 0; j < walletCount; j++) {
                address wallet = participantWallets.at(j);
                WalletState storage walletState = $.walletStates[wallet];
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
        SharedWalletControllerStorage storage $ = _getStorage();
        return $.walletStates[wallet].participants;
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function getWalletOverviews(address[] calldata wallets) external view returns (WalletOverview[] memory overviews) {
        SharedWalletControllerStorage storage $ = _getStorage();

        uint256 walletCount = wallets.length;
        overviews = new WalletOverview[](walletCount);

        for (uint256 i = 0; i < walletCount; i++) {
            address wallet = wallets[i];
            WalletState storage walletState = $.walletStates[wallet];

            uint256 participantCount = walletState.participants.length;
            ParticipantSummary[] memory participantSummaries = new ParticipantSummary[](participantCount);

            for (uint256 j = 0; j < participantCount; j++) {
                address participant = walletState.participants[j];
                ParticipantState storage participantState = walletState.participantStates[participant];

                participantSummaries[j] = ParticipantSummary({
                    participant: participant,
                    participantStatus: participantState.status,
                    participantBalance: participantState.balance
                });
            }

            overviews[i] = WalletOverview({
                wallet: wallet,
                walletStatus: walletState.status,
                walletBalance: walletState.balance,
                participantSummaries: participantSummaries
            });
        }
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
        SharedWalletControllerStorage storage $ = _getStorage();

        WalletParticipantPair[] memory normalizedPairs = _normalizeWalletParticipantPairs(pairs, $);
        uint256 normalizedPairCount = normalizedPairs.length;
        overviews = new WalletParticipantOverview[](normalizedPairCount);

        for (uint256 i = 0; i < normalizedPairCount; i++) {
            address wallet = normalizedPairs[i].wallet;
            address participant = normalizedPairs[i].participant;
            WalletState storage walletState = $.walletStates[wallet];
            ParticipantState storage participantState = walletState.participantStates[participant];

            overviews[i] = WalletParticipantOverview({
                wallet: wallet,
                walletStatus: walletState.status,
                walletBalance: walletState.balance,
                participant: participant,
                participantStatus: participantState.status,
                participantBalance: participantState.balance
            });
        }
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function getWalletCount() external view returns (uint256) {
        SharedWalletControllerStorage storage $ = _getStorage();
        return $.walletCount;
    }

    /**
     * @inheritdoc ISharedWalletControllerPrimary
     */
    function getAggregatedBalance() external view returns (uint256) {
        SharedWalletControllerStorage storage $ = _getStorage();
        return $.aggregatedBalance;
    }

    // ------------------ Pure functions -------------------------- //

    /// @inheritdoc ISharedWalletController
    function proveSharedWalletController() external pure {}

    // ------------------ Internal functions ---------------------- //

    /**
     * @dev Returns a shared wallet by its address after ensuring it exists.
     * @param wallet The address of the wallet.
     * @param $ The shared wallet controller storage reference.
     * @return The shared wallet as a storage reference.
     */
    function _getExistentWallet(
        address wallet,
        SharedWalletControllerStorage storage $
    ) internal view returns (WalletState storage) {
        WalletState storage walletState = $.walletStates[wallet];
        if (walletState.status == WalletStatus.Nonexistent) {
            revert SharedWalletController_WalletNonexistent();
        }
        return walletState;
    }

    /**
     * @dev Increases the number of existing shared wallets by 1.
     * @param $ The shared wallet controller storage reference.
     */
    function _safeIncrementWalletCount(SharedWalletControllerStorage storage $) internal {
        if ($.walletCount == type(uint32).max) {
            revert SharedWalletController_WalletCountExceedsLimit();
        }
        $.walletCount += 1;
    }

    /**
     * @dev Adds a participant to a wallet.
     * @param wallet The address of the wallet.
     * @param participant The address of the participant.
     * @param walletState The wallet state storage reference.
     * @param $ The shared wallet controller storage reference.
     */
    function _addParticipant(
        address wallet,
        address participant,
        WalletState storage walletState,
        SharedWalletControllerStorage storage $
    ) internal {
        if (participant == address(0)) {
            revert SharedWalletController_ParticipantAddressZero();
        }

        ParticipantState storage participantState = walletState.participantStates[participant];

        if (participantState.status != ParticipantStatus.NotRegistered) {
            revert SharedWalletController_ParticipantAlreadyRegistered();
        }
        if ($.walletStates[participant].status != WalletStatus.Nonexistent) {
            revert SharedWalletController_ParticipantIsSharedWallet();
        }
        if (walletState.participants.length >= MAX_PARTICIPANTS_PER_WALLET) {
            revert SharedWalletController_ParticipantCountExceedsLimit();
        }

        uint256 newParticipantIndex = walletState.participants.length;
        walletState.participants.push(participant);

        participantState.status = ParticipantStatus.Registered;
        participantState.index = uint16(newParticipantIndex);
        participantState.balance = 0;

        $.participantWallets[participant].add(wallet);

        emit ParticipantAdded(wallet, participant);
    }

    /**
     * @dev Removes a participant from a wallet.
     * @param wallet The address of the wallet.
     * @param participant The address of the participant.
     * @param walletState The shared wallet storage reference.
     * @param $ The shared wallet controller storage reference.
     */
    function _removeParticipant(
        address wallet,
        address participant,
        WalletState storage walletState,
        SharedWalletControllerStorage storage $
    ) internal {
        if (walletState.participantStates[participant].status == ParticipantStatus.NotRegistered) {
            revert SharedWalletController_ParticipantNotRegistered(participant);
        }
        if (walletState.participantStates[participant].balance > 0) {
            revert SharedWalletController_ParticipantBalanceNotZero(participant);
        }

        _removeParticipantFromWallet(walletState, participant);
        _removeWalletFromParticipant(wallet, participant, $);

        emit ParticipantRemoved(wallet, participant);
    }

    /**
     * @dev Removes a participant from the wallet's participants array and state mapping.
     *
     * Uses the swap-and-pop algorithm to maintain array order while avoiding gas-expensive shifts.
     * The participant at the target index is replaced with the last participant, then the array is shortened.
     *
     * @param walletState The shared wallet storage reference.
     * @param participant The address of the participant to remove.
     */
    function _removeParticipantFromWallet(WalletState storage walletState, address participant) internal {
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
     * @param wallet The address of the wallet to remove.
     * @param participant The address of the participant.
     * @param $ The shared wallet controller storage reference.
     */
    function _removeWalletFromParticipant(
        address wallet,
        address participant,
        SharedWalletControllerStorage storage $
    ) internal {
        $.participantWallets[participant].remove(wallet);
    }

    /**
     * @dev Handles an outgoing transfer from a wallet.
     * @param wallet The address of the wallet.
     * @param to The address of the recipient.
     * @param amount The amount of the transfer.
     * @param walletState The wallet state storage reference.
     * @param $ The shared wallet controller storage reference.
     */
    function _handleOutgoingTransfer(
        address wallet,
        address to,
        uint256 amount,
        WalletState storage walletState,
        SharedWalletControllerStorage storage $
    ) internal {
        if (walletState.participantStates[to].status == ParticipantStatus.Registered) {
            _processParticipantTransfer(wallet, to, amount, uint256(TransferDirection.Out), walletState, $);
        } else {
            _processExternalTransfer(wallet, amount, uint256(TransferDirection.Out), walletState, $);
        }
    }

    /**
     * @dev Handles an incoming transfer to a wallet.
     * @param from The address of the sender.
     * @param wallet The address of the wallet.
     * @param amount The amount of the transfer.
     * @param walletState The wallet state storage reference.
     * @param $ The shared wallet controller storage reference.
     */
    function _handleIncomingTransfer(
        address from,
        address wallet,
        uint256 amount,
        WalletState storage walletState,
        SharedWalletControllerStorage storage $
    ) internal {
        if (walletState.participantStates[from].status == ParticipantStatus.Registered) {
            _processParticipantTransfer(wallet, from, amount, uint256(TransferDirection.In), walletState, $);
        } else {
            _processExternalTransfer(wallet, amount, uint256(TransferDirection.In), walletState, $);
        }
    }

    /**
     * @dev Processes a transfer operation between a participant and the wallet.
     * @param wallet The address of the wallet.
     * @param participant The address of the participant.
     * @param amount The amount of the operation.
     * @param transferDirection The direction of transfer according to the {TransferDirection} enum.
     * @param walletState The wallet state storage reference.
     * @param $ The shared wallet controller storage reference.
     */
    function _processParticipantTransfer(
        address wallet,
        address participant,
        uint256 amount,
        uint256 transferDirection,
        WalletState storage walletState,
        SharedWalletControllerStorage storage $
    ) internal {
        ParticipantState storage participantState = walletState.participantStates[participant];
        uint256 oldWalletBalance = walletState.balance;
        uint256 newWalletBalance;
        uint256 oldParticipantBalance = participantState.balance;
        uint256 newParticipantBalance;

        if (transferDirection == uint256(TransferDirection.In)) {
            newParticipantBalance = oldParticipantBalance + amount;
            newWalletBalance = oldWalletBalance + amount;
            _increaseAggregatedBalance(amount, $);

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
                $.aggregatedBalance -= uint64(amount);
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
     * @dev Processes a transfer from external sources that gets distributed among participants in a wallet.
     * @param wallet The address of the wallet.
     * @param amount The amount of tokens to distribute.
     * @param transferDirection The direction of transfer according to the {TransferDirection} enum.
     * @param walletState The wallet state storage reference.
     * @param $ The shared wallet controller storage reference.
     */
    function _processExternalTransfer(
        address wallet,
        uint256 amount,
        uint256 transferDirection,
        WalletState storage walletState,
        SharedWalletControllerStorage storage $
    ) internal {
        uint256 oldWalletBalance = walletState.balance;
        uint256 newWalletBalance;

        if (transferDirection == uint256(TransferDirection.In)) {
            newWalletBalance = oldWalletBalance + amount;
            _increaseAggregatedBalance(amount, $);
        } else {
            if (oldWalletBalance < amount) {
                revert SharedWalletController_WalletBalanceInsufficient();
            }
            unchecked {
                newWalletBalance = oldWalletBalance - amount;
                $.aggregatedBalance -= uint64(amount);
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
                        revert SharedWalletController_SharesCalculationInvalid();
                    }
                    unchecked {
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
     * @dev Increases the aggregated balance across all shared wallets by the given amount.
     * @param amount The amount to increase the aggregated balance by.
     * @param $ The shared wallet controller storage reference.
     */
    function _increaseAggregatedBalance(uint256 amount, SharedWalletControllerStorage storage $) internal {
        uint256 newAggregatedBalance = uint256($.aggregatedBalance) + amount;
        if (newAggregatedBalance > type(uint64).max) {
            revert SharedWalletController_AggregatedBalanceExceedsLimit();
        }
        $.aggregatedBalance = uint64(newAggregatedBalance);
    }

    /**
     * @dev Calculates the shares of participants in a transfer based on their proportional balances.
     *
     * If the wallet has a balance, shares are distributed proportionally to participant balances.
     * If the wallet has zero balance, shares are distributed equally among all participants.
     * Any remainder due to rounding is assigned to the participant with the largest share.
     *
     * @param amount The amount of the transfer to distribute.
     * @param walletState The shared wallet storage reference.
     * @return The calculated shares for each participant in the same order as the participants array.
     */
    function _calculateParticipantShares(
        uint256 amount,
        WalletState storage walletState
    ) internal view returns (uint256[] memory) {
        uint256 i = walletState.participants.length;
        uint256[] memory shares = new uint256[](i);
        uint256 totalBalance = walletState.balance;
        uint256 totalShares = 0;
        uint256 biggestShareIndex = 0;
        uint256 biggestShareAmount = 0;

        if (totalBalance != 0) {
            do {
                --i;
                uint256 participantBalance = walletState.participantStates[walletState.participants[i]].balance;
                if (participantBalance > 0) {
                    uint256 share = _calculateShare(amount, participantBalance, totalBalance);
                    totalShares += share;
                    shares[i] = share;
                    if (share > biggestShareAmount) {
                        biggestShareAmount = share;
                        biggestShareIndex = i;
                    }
                }
            } while (i != 0);
        } else {
            uint256 share = _calculateShare(amount, 1, i);
            totalShares = share * i;
            do {
                --i;
                shares[i] = share;
            } while (i != 0);
        }

        shares[biggestShareIndex] += amount - totalShares;
        return shares;
    }

    /**
     * @dev Calculates a participant's share of a transfer amount based on their proportional balance.
     *
     * The calculation applies the accuracy factor to round down the result to avoid dust amounts.
     *
     * @param amount The total amount to distribute.
     * @param balance The participant's balance.
     * @param totalBalance The total balance of all participants.
     * @return The participant's calculated share, rounded down to the accuracy factor.
     */
    function _calculateShare(uint256 amount, uint256 balance, uint256 totalBalance) internal pure returns (uint256) {
        uint256 share = (amount * balance) / totalBalance;
        return (share / ACCURACY_FACTOR) * ACCURACY_FACTOR; // Round down according to the accuracy factor
    }

    /**
     * @dev Expands wallet-participant pairs that contain zero addresses (wildcards) into concrete pairs.
     *
     * Zero addresses act as wildcards:
     * - Zero wallet address: expands to all wallets containing the specified participant
     * - Zero participant address: expands to all participants in the specified wallet
     * - Both specified: returns the pair as-is
     *
     * @param pairs The wallet-participant pairs that may contain zero address wildcards.
     * @param $ The shared wallet controller storage reference.
     * @return The expanded pairs with all wildcards resolved to concrete addresses.
     */
    function _normalizeWalletParticipantPairs(
        WalletParticipantPair[] calldata pairs,
        SharedWalletControllerStorage storage $
    ) internal view returns (WalletParticipantPair[] memory) {
        uint256 initialPairCount = pairs.length;

        // First pass: count actual pairs and validate
        uint256 actualPairCount = 0;
        for (uint256 i = 0; i < initialPairCount; i++) {
            WalletParticipantPair calldata pair = pairs[i];

            if (pair.wallet == address(0) && pair.participant == address(0)) {
                revert SharedWalletController_WalletAndParticipantAddressesBothZero();
            }

            if (pair.wallet == address(0)) {
                actualPairCount += $.participantWallets[pair.participant].length();
            } else if (pair.participant == address(0)) {
                actualPairCount += $.walletStates[pair.wallet].participants.length;
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
                EnumerableSet.AddressSet storage participantWallets = $.participantWallets[pair.participant];
                uint256 walletCount = participantWallets.length();
                for (uint256 j = 0; j < walletCount; j++) {
                    actualPairs[pairIndex++] = WalletParticipantPair(participantWallets.at(j), pair.participant);
                }
            } else if (pair.participant == address(0)) {
                WalletState storage walletState = $.walletStates[pair.wallet];
                uint256 participantCount = walletState.participants.length;
                for (uint256 j = 0; j < participantCount; j++) {
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
            revert SharedWalletController_ImplementationInvalid();
        }
    }
}
