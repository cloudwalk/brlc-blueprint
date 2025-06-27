SharedWalletController Key point:
1. The first participant (index 0) has a special meaning: the initiator (owner) of a shared wallet.
2. The first participant is not allowed to be removed from a shared wallet.
3. Incoming tokens to a wallet are treated as:
    * The `Deposit` operation if the sender is a participant of the wallet.
    * The `Transfer In` operation if the sender is not a participant of the wallet.
4. Outcoming tokens from a wallet are treated as:
    * The `Withdraw` operation if the receiver is a participant of the wallet.
    * The `Transfer Out` operation if the receiver is not a participant of the wallet.
5. Operations `Deposit` and `Withdraw` are together named funding operations.
6. Operations `Transfer In` and `Transfer Out` are together named transfer operations.
7. The transfer operation tokens are always distributed among all participants within a wallet proportionally to their balance.
8. Token distribution shares are rounded down according to the constant `ACCURACY_FACTOR` (10000, which corresponds to 0.01 BRLC).
9. Due to rounding, the participant of a wallet with non-zero balance and the lowest index might get a bit more or bit less tokens than the others within a transfer operation.
10. Input transfers to a wallet that has the zero balance are always distributed equally among all participants. It happens because shares cannot be calculated in this case. Alternatively, we can move tokens in that case to the first participant only.
11. A address that already belongs to a shared wallet cannot be registered as a participant of any shared wallet.
12. IMPORTANT!. There is NO protection on the contract side against registration of common wallet address as a shared one. It will have bad consequences and must be strictly controlled by the backend.
13. Wallet states:
    * Nonexistent: initial state, when the wallet does not exist.
    * Active: when the wallet is created and active.
    * Deactivated: when the wallet is deactivated.
14. Valid state transitions for a shared wallet:
    * Creation by an admin: Nonexistent -> Active
    * Deactivation by an admin: Active -> Deactivated
    * Reactivation by an admin: Deactivated -> Active
    * Removal by an owner: Deactivated -> Nonexistent
15. A wallet with a nonzero balance cannot be deactivated or removed.
16. IMPORTANT! Wallet removing can be made only by account that has the owner role in the controller contract.
17. Any transfers to or from a deactivated wallet will cause the transaction to revert.
18. A participant with a nonzero balance cannot be removed from the wallet.