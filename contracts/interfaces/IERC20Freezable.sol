// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title IERC20Freezable interface
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev The interface of a token that supports freezing operations.
 */
interface IERC20Freezable {
    /**
     * @dev Updates the frozen balance of an account.
     *
     * @param account The account to update the frozen balance for.
     * @param amount The amount of tokens to set as the new frozen balance.
     * @return newBalance The frozen balance of the account after the update.
     * @return oldBalance The frozen balance of the account before the update.
     */
    function freeze(
        address account, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 amount
    ) external returns (uint256 newBalance, uint256 oldBalance);

    /**
     * @dev Increases the frozen balance of an account.
     *
     * @param account The account to increase frozen balance for.
     * @param amount The amount to increase the frozen balance by.
     * @return newBalance The frozen balance of the account after the increase.
     * @return oldBalance The frozen balance of the account before the increase.
     */
    function freezeIncrease(
        address account, // Tools: this comment prevents Prettier from formatting into a single line
        uint256 amount
    ) external returns (uint256 newBalance, uint256 oldBalance);

    /**
     * @dev Decreases the frozen balance of an account.
     *
     * @param account The account to decrease frozen balance for.
     * @param amount The amount to decrease the frozen balance by.
     * @return newBalance The frozen balance of the account after the decrease.
     * @return oldBalance The frozen balance of the account before the decrease.
     */
    function freezeDecrease(
        address account, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 amount
    ) external returns (uint256 newBalance, uint256 oldBalance);

    /**
     * @dev Transfers frozen tokens on behalf of an account.
     *
     * @param from The account tokens will be transferred from
     * @param to The account tokens will be transferred to
     * @param amount The amount of tokens to transfer
     * @return newBalance The frozen balance of the `from` account after the transfer
     * @return oldBalance The frozen balance of the `from` account before the transfer
     */
    function transferFrozen(
        address from, // Tools: this comment prevents Prettier from formatting into a single line.
        address to,
        uint256 amount
    ) external returns (uint256 newBalance, uint256 oldBalance);

    /**
     * @dev Retrieves the frozen balance of an account.
     *
     * @param account The account to check the balance of.
     * @return The amount of tokens that are frozen for the account.
     */
    function balanceOfFrozen(address account) external view returns (uint256);
}
