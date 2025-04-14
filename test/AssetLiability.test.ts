import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import { Contract, ContractFactory, TransactionResponse } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { checkContractUupsUpgrading, connect, getAddress, proveTx } from "../test-utils/eth";
import { checkEquality, maxUintForBits, setUpFixture } from "../test-utils/common";

const EXPECTED_VERSION: Version = {
    major: 1,
    minor: 0,
    patch: 0
  };

const ROLES = {
  OWNER_ROLE: ethers.id("OWNER_ROLE"),
  PAUSER_ROLE: ethers.id("PAUSER_ROLE"),
  MANAGER_ROLE: ethers.id("MANAGER_ROLE")
};

const EVENTS = {
    LiabilityUpdated: "LiabilityUpdated",
    TreasuryUpdated: "TreasuryUpdated"
};

const ERRORS = {
    AssetLiability_InvalidInitialization: "InvalidInitialization",
    AssetLiability_AccessControlUnauthorizedAccount: "AccessControlUnauthorizedAccount",
    AssetLiability_ImplementationAddressInvalid: "AssetLiability_ImplementationAddressInvalid",
    AssetLiability_UnderlyingTokenAddressZero: "AssetLiability_UnderlyingTokenAddressZero",
    AssetLiability_TreasuryAddressAlreadySet: "AssetLiability_TreasuryAddressAlreadySet",
    AssetLiability_AccountsAndAmountsLengthMismatch: "AssetLiability_AccountsAndAmountsLengthMismatch",
    AssetLiability_AccountAddressZero: "AssetLiability_AccountAddressZero",
    AssetLiability_AmountZero: "AssetLiability_AmountZero",
    AssetLiability_DecreaseAmountExcess: "AssetLiability_DecreaseAmountExcess",
    AssetLiability_AmountOverflow: "AssetLiability_AmountOverflow",
    EnforcedPause: "EnforcedPause"
}

const ADDRESS_ZERO = ethers.ZeroAddress;
const ALLOWANCE_MAX = ethers.MaxUint256;
const BALANCE_INITIAL = 1000_000_000_000n;

const LIABILITY_AMOUNT = 12345678;
const LIABILITY_AMOUNTS: number[] = [
  LIABILITY_AMOUNT,
  LIABILITY_AMOUNT * 2,
  LIABILITY_AMOUNT * 3,
  LIABILITY_AMOUNT * 4,
  LIABILITY_AMOUNT * 5
];

interface Version {
  major: number;
  minor: number;
  patch: number;

  [key: string]: number; // Indexing signature to ensure that fields are iterated over in a key-value style
}

interface Liability {
  amount: bigint;

  [key: string]: bigint; // Indexing signature to ensure that fields are iterated over in a key-value style
}

const defaultLiability: Liability = {
  amount: 0n
};

interface Fixture {
  assetLiability: Contract;
  tokenMock: Contract;
}

describe("Contract 'AssetLiability'", async () => {
  let assetLiabilityFactory: ContractFactory;

  let deployer: HardhatEthersSigner;
  let manager: HardhatEthersSigner;
  let treasury: HardhatEthersSigner;
  let stranger: HardhatEthersSigner;
  let user: HardhatEthersSigner;
  let users: HardhatEthersSigner[];

  before(async () => {
    let moreUsers: HardhatEthersSigner[];
    [deployer, manager, treasury, stranger, user, ...moreUsers] = await ethers.getSigners();
    users = [user, ...moreUsers];

    // The contract factories with the explicitly specified deployer account
    assetLiabilityFactory = await ethers.getContractFactory("AssetLiability");
    assetLiabilityFactory = assetLiabilityFactory.connect(deployer);
  });

  async function deployTokenMock(): Promise<Contract> {
    const name = "ERC20 Test";
    const symbol = "TEST";

    // The token contract factory with the explicitly specified deployer account
    let tokenMockFactory = await ethers.getContractFactory("ERC20TokenMock");
    tokenMockFactory = tokenMockFactory.connect(deployer);

    // The token contract with the explicitly specified initial account
    let tokenMock: Contract = await tokenMockFactory.deploy(name, symbol) as Contract;
    await tokenMock.waitForDeployment();
    tokenMock = connect(tokenMock, deployer); // Explicitly specifying the initial account

    return tokenMock;
  }

  async function deployContracts(): Promise<Fixture> {
    const tokenMock = await deployTokenMock();
    let assetLiability: Contract = await upgrades.deployProxy(assetLiabilityFactory, [getAddress(tokenMock)]) as Contract;
    await assetLiability.waitForDeployment();
    assetLiability = connect(assetLiability, deployer); // Explicitly specifying the initial account

    return {
      assetLiability,
      tokenMock
    };
  }

  async function deployAndConfigureContracts(): Promise<Fixture> {
    const fixture = await deployContracts();
    const { assetLiability, tokenMock } = fixture;

    await proveTx(assetLiability.grantRole(ROLES.MANAGER_ROLE, manager.address));
    await proveTx(assetLiability.setOperationalTreasury(treasury.address));

    // Mint initial balances
    await proveTx(tokenMock.mint(treasury.address, BALANCE_INITIAL));
    for (let i = 0; i < LIABILITY_AMOUNTS.length; ++i) {
      const account = users[i].address;
      await proveTx(tokenMock.mint(account, BALANCE_INITIAL));
    }

    // Approvals
    await proveTx(connect(tokenMock, treasury).approve(getAddress(assetLiability), ALLOWANCE_MAX));

    return fixture;
  }

  async function pauseContract(contract: Contract) {
    await proveTx(contract.grantRole(ROLES.PAUSER_ROLE, deployer.address));
    await proveTx(contract.pause());
  }

  describe("Function 'initialize()'", async () => {
    it("Configures the contract as expected", async () => {
      const { assetLiability, tokenMock } = await setUpFixture(deployContracts);

      // The underlying token contract address
      expect(await assetLiability.underlyingToken()).to.equal(getAddress(tokenMock));

      // Role hashes
      expect(await assetLiability.OWNER_ROLE()).to.equal(ROLES.OWNER_ROLE);
      expect(await assetLiability.MANAGER_ROLE()).to.equal(ROLES.MANAGER_ROLE);

      // The role admins
      expect(await assetLiability.getRoleAdmin(ROLES.OWNER_ROLE)).to.equal(ROLES.OWNER_ROLE);
      expect(await assetLiability.getRoleAdmin(ROLES.MANAGER_ROLE)).to.equal(ROLES.OWNER_ROLE);

      // The deployer should have the owner role, but not the other roles
      expect(await assetLiability.hasRole(ROLES.OWNER_ROLE, deployer.address)).to.equal(true);
      expect(await assetLiability.hasRole(ROLES.MANAGER_ROLE, deployer.address)).to.equal(false);

      // Default values for treasury and total liability
      expect(await assetLiability.operationalTreasury()).to.equal(ADDRESS_ZERO);
      expect(await assetLiability.totalLiability()).to.equal(0);
    });

    it("Is reverted if it is called a second time", async () => {
      const { assetLiability, tokenMock } = await setUpFixture(deployContracts);
      await expect(
        assetLiability.initialize(getAddress(tokenMock))
      ).to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_InvalidInitialization);
    });

    it("Is reverted if the passed token address is zero", async () => {
      const anotherAssetLiabilityContract: Contract = await upgrades.deployProxy(
        assetLiabilityFactory,
        [],
        { initializer: false }
      ) as Contract;

      await expect(
        anotherAssetLiabilityContract.initialize(ADDRESS_ZERO)
      ).to.be.revertedWithCustomError(assetLiabilityFactory, ERRORS.AssetLiability_UnderlyingTokenAddressZero);
    });
  });

  describe("Function 'upgradeToAndCall()'", async () => {
    it("Executes as expected", async () => {
      const { assetLiability } = await setUpFixture(deployContracts);
      await checkContractUupsUpgrading(assetLiability, assetLiabilityFactory);
    });

    it("Is reverted if the caller does not have the owner role", async () => {
      const { assetLiability } = await setUpFixture(deployContracts);

      await expect(connect(assetLiability, user).upgradeToAndCall(getAddress(assetLiability), "0x"))
        .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AccessControlUnauthorizedAccount)
        .withArgs(user.address, ROLES.OWNER_ROLE);
    });

    it("Is reverted if the provided implementation address does not belong to an AssetLiability contract", async () => {
      const { assetLiability, tokenMock } = await setUpFixture(deployContracts);

      await expect(assetLiability.upgradeToAndCall(getAddress(tokenMock), "0x"))
        .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_ImplementationAddressInvalid);
    });
  });

  describe("Function '$__VERSION()'", async () => {
    it("Returns expected values", async () => {
      const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
      const assetLiabilityVersion = await assetLiability.$__VERSION();
      checkEquality(assetLiabilityVersion, EXPECTED_VERSION);
    });
  });

  describe("Function 'setOperationalTreasury()'", async () => {
    it("Executes as expected and emits the correct event", async () => {
      const { assetLiability } = await setUpFixture(deployContracts);

      await expect(assetLiability.setOperationalTreasury(treasury.address))
        .to.emit(assetLiability, EVENTS.TreasuryUpdated)
        .withArgs(treasury.address, ADDRESS_ZERO);

      expect(await assetLiability.operationalTreasury()).to.eq(treasury.address);
    });

    it("Is reverted if caller does not have the owner role", async () => {
      const { assetLiability } = await setUpFixture(deployContracts);

      await expect(connect(assetLiability, stranger).setOperationalTreasury(treasury.address))
        .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AccessControlUnauthorizedAccount)
        .withArgs(stranger.address, ROLES.OWNER_ROLE);
    });

    it("Is reverted if the new treasury address is the same as the previous one", async () => {
      const { assetLiability } = await setUpFixture(deployContracts);

      // First set the treasury
      await proveTx(assetLiability.setOperationalTreasury(treasury.address));

      // Now try to set it to the same address
      await expect(assetLiability.setOperationalTreasury(treasury.address))
        .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_TreasuryAddressAlreadySet);
    });
  });

  describe("Function 'transferWithLiability()'", async () => {
    describe("Executes as expected if", async () => {
      it("The transfer is for a single account", async () => {
        const { assetLiability, tokenMock } = await setUpFixture(deployAndConfigureContracts);
        const amount = BigInt(LIABILITY_AMOUNT);
        const account = user.address;

        // First check the event emission
        await expect(connect(assetLiability, manager).transferWithLiability([account], [amount]))
          .to.emit(assetLiability, EVENTS.LiabilityUpdated)
          .withArgs(account, amount, 0);

        // Then check the token balances change in a separate test
        await expect(() =>
          connect(assetLiability, manager).transferWithLiability([account], [amount])
        ).to.changeTokenBalances(
          tokenMock,
          [treasury.address, account],
          [-amount, amount]
        );

        expect(await assetLiability.liabilityOf(account)).to.equal(amount * 2n); // x2 because we called it twice
        expect(await assetLiability.totalLiability()).to.equal(amount * 2n);
      });

      it("The transfer is for multiple accounts", async () => {
        const { assetLiability, tokenMock } = await setUpFixture(deployAndConfigureContracts);
        const accounts = users.slice(0, 3).map(user => user.address);
        const amounts = LIABILITY_AMOUNTS.slice(0, 3).map(BigInt);
        const totalAmount = amounts.reduce((acc, val) => acc + val, 0n);

        // Check that the function emits the correct events
        const tx = await connect(assetLiability, manager).transferWithLiability(accounts, amounts);
        await expect(tx)
          .to.emit(assetLiability, EVENTS.LiabilityUpdated)
          .withArgs(accounts[0], amounts[0], 0);
        await expect(tx)
          .to.emit(assetLiability, EVENTS.LiabilityUpdated)
          .withArgs(accounts[1], amounts[1], 0);
        await expect(tx)
          .to.emit(assetLiability, EVENTS.LiabilityUpdated)
          .withArgs(accounts[2], amounts[2], 0);

        // Check the final state
        expect(await assetLiability.liabilityOf(accounts[0])).to.equal(amounts[0]);
        expect(await assetLiability.liabilityOf(accounts[1])).to.equal(amounts[1]);
        expect(await assetLiability.liabilityOf(accounts[2])).to.equal(amounts[2]);
        expect(await assetLiability.totalLiability()).to.equal(totalAmount);

        // Check the token balances separately for each account
        for (let i = 0; i < accounts.length; i++) {
          await expect(() =>
            connect(assetLiability, manager).transferWithLiability([accounts[i]], [amounts[i]])
          ).to.changeTokenBalances(
            tokenMock,
            [treasury.address, accounts[i]],
            [-amounts[i], amounts[i]]
          );
        }
      });
    });

    describe("Is reverted if", async () => {
      it("The arrays length mismatch", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
        const accounts = [user.address, users[1].address];
        const amounts = [BigInt(LIABILITY_AMOUNT)];

        await expect(connect(assetLiability, manager).transferWithLiability(accounts, amounts))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AccountsAndAmountsLengthMismatch);
      });

      it("The caller lacks MANAGER_ROLE", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);

        await expect(connect(assetLiability, stranger).transferWithLiability([user.address], [BigInt(LIABILITY_AMOUNT)]))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AccessControlUnauthorizedAccount)
          .withArgs(stranger.address, ROLES.MANAGER_ROLE);
      });

      it("The account address is zero", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);

        await expect(connect(assetLiability, manager).transferWithLiability([ADDRESS_ZERO], [BigInt(LIABILITY_AMOUNT)]))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AccountAddressZero);
      });

      it("The amount is zero", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);

        await expect(connect(assetLiability, manager).transferWithLiability([user.address], [0]))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AmountZero);
      });

      it("The amount exceeds uint64 max", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
        const maxUint64 = maxUintForBits(64);
        const amount = maxUint64 + 1n;
        const account = user.address;

        await expect(connect(assetLiability, manager).transferWithLiability([account], [amount]))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AmountOverflow);
      });

      it("The contract is paused", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);

        // Pause the contract
        await pauseContract(assetLiability);

        await expect(connect(assetLiability, manager).transferWithLiability([user.address], [BigInt(LIABILITY_AMOUNT)]))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.EnforcedPause);
      });
    });
  });

  describe("Function 'increaseLiability()'", async () => {
    describe("Executes as expected if", async () => {
      it("The liability is increased for a single account", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
        const amount = BigInt(LIABILITY_AMOUNT);
        const account = user.address;

        await expect(connect(assetLiability, manager).increaseLiability([account], [amount]))
          .to.emit(assetLiability, EVENTS.LiabilityUpdated)
          .withArgs(account, amount, 0);

        expect(await assetLiability.liabilityOf(account)).to.equal(amount);
        expect(await assetLiability.totalLiability()).to.equal(amount);
      });

      it("The liability is increased for multiple accounts", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
        const accounts = users.slice(0, 3).map(user => user.address);
        const amounts = LIABILITY_AMOUNTS.slice(0, 3).map(BigInt);
        const totalAmount = amounts.reduce((acc, val) => acc + val, 0n);

        await expect(connect(assetLiability, manager).increaseLiability(accounts, amounts))
          .to.emit(assetLiability, EVENTS.LiabilityUpdated)
          .withArgs(accounts[0], amounts[0], 0)
          .to.emit(assetLiability, EVENTS.LiabilityUpdated)
          .withArgs(accounts[1], amounts[1], 0)
          .to.emit(assetLiability, EVENTS.LiabilityUpdated)
          .withArgs(accounts[2], amounts[2], 0);

        expect(await assetLiability.liabilityOf(accounts[0])).to.equal(amounts[0]);
        expect(await assetLiability.liabilityOf(accounts[1])).to.equal(amounts[1]);
        expect(await assetLiability.liabilityOf(accounts[2])).to.equal(amounts[2]);
        expect(await assetLiability.totalLiability()).to.equal(totalAmount);
      });

      it("The account already has a liability", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
        const amount1 = BigInt(LIABILITY_AMOUNT);
        const amount2 = BigInt(LIABILITY_AMOUNT * 2);
        const account = user.address;

        // First increase
        await proveTx(connect(assetLiability, manager).increaseLiability([account], [amount1]));

        // Second increase
        await expect(connect(assetLiability, manager).increaseLiability([account], [amount2]))
          .to.emit(assetLiability, EVENTS.LiabilityUpdated)
          .withArgs(account, amount1 + amount2, amount1);

        expect(await assetLiability.liabilityOf(account)).to.equal(amount1 + amount2);
        expect(await assetLiability.totalLiability()).to.equal(amount1 + amount2);
      });
    });

    describe("Is reverted if", async () => {
      it("The arrays length mismatch", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
        const accounts = [user.address, users[1].address];
        const amounts = [BigInt(LIABILITY_AMOUNT)];

        await expect(connect(assetLiability, manager).increaseLiability(accounts, amounts))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AccountsAndAmountsLengthMismatch);
      });

      it("The caller lacks MANAGER_ROLE", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);

        await expect(connect(assetLiability, stranger).increaseLiability([user.address], [BigInt(LIABILITY_AMOUNT)]))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AccessControlUnauthorizedAccount)
          .withArgs(stranger.address, ROLES.MANAGER_ROLE);
      });

      it("The account address is zero", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);

        await expect(connect(assetLiability, manager).increaseLiability([ADDRESS_ZERO], [BigInt(LIABILITY_AMOUNT)]))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AccountAddressZero);
      });

      it("The amount is zero", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);

        await expect(connect(assetLiability, manager).increaseLiability([user.address], [0]))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AmountZero);
      });

      it("The amount exceeds uint64 max", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
        const maxUint64 = maxUintForBits(64);
        const amount = maxUint64 + 1n;
        const account = user.address;

        await expect(connect(assetLiability, manager).increaseLiability([account], [amount]))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AmountOverflow);
      });

      it("The contract is paused", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);

        // Pause the contract
        await pauseContract(assetLiability);

        await expect(connect(assetLiability, manager).increaseLiability([user.address], [BigInt(LIABILITY_AMOUNT)]))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.EnforcedPause);
      });
    });
  });

  describe("Function 'decreaseLiability()'", async () => {
    describe("Executes as expected if", async () => {
      it("The decrease is for a single account's full liability", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
        const amount = BigInt(LIABILITY_AMOUNT);
        const account = user.address;

        // First create a liability
        await proveTx(connect(assetLiability, manager).increaseLiability([account], [amount]));

        // Then decrease it
        await expect(connect(assetLiability, manager).decreaseLiability([account], [amount]))
          .to.emit(assetLiability, EVENTS.LiabilityUpdated)
          .withArgs(account, 0, amount);

        expect(await assetLiability.liabilityOf(account)).to.equal(0);
        expect(await assetLiability.totalLiability()).to.equal(0);
      });

      it("The decrease is for multiple accounts", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
        const accounts = users.slice(0, 3).map(user => user.address);
        const amounts = LIABILITY_AMOUNTS.slice(0, 3).map(BigInt);

        // First create liabilities
        await proveTx(connect(assetLiability, manager).increaseLiability(accounts, amounts));

        // Then decrease them
        await expect(connect(assetLiability, manager).decreaseLiability(accounts, amounts))
          .to.emit(assetLiability, EVENTS.LiabilityUpdated)
          .withArgs(accounts[0], 0, amounts[0])
          .to.emit(assetLiability, EVENTS.LiabilityUpdated)
          .withArgs(accounts[1], 0, amounts[1])
          .to.emit(assetLiability, EVENTS.LiabilityUpdated)
          .withArgs(accounts[2], 0, amounts[2]);

        expect(await assetLiability.liabilityOf(accounts[0])).to.equal(0);
        expect(await assetLiability.liabilityOf(accounts[1])).to.equal(0);
        expect(await assetLiability.liabilityOf(accounts[2])).to.equal(0);
        expect(await assetLiability.totalLiability()).to.equal(0);
      });

      it("The decrease is partial", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
        const fullAmount = BigInt(LIABILITY_AMOUNT);
        const partialAmount = BigInt(LIABILITY_AMOUNT / 2);
        const account = user.address;

        // First create a liability
        await proveTx(connect(assetLiability, manager).increaseLiability([account], [fullAmount]));

        // Then decrease partially
        await expect(connect(assetLiability, manager).decreaseLiability([account], [partialAmount]))
          .to.emit(assetLiability, EVENTS.LiabilityUpdated)
          .withArgs(account, fullAmount - partialAmount, fullAmount);

        expect(await assetLiability.liabilityOf(account)).to.equal(fullAmount - partialAmount);
        expect(await assetLiability.totalLiability()).to.equal(fullAmount - partialAmount);
      });
    });

    describe("Is reverted if", async () => {
      it("The arrays length mismatch", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
        const accounts = [user.address, users[1].address];
        const amounts = [BigInt(LIABILITY_AMOUNT)];

        await expect(connect(assetLiability, manager).decreaseLiability(accounts, amounts))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AccountsAndAmountsLengthMismatch);
      });

      it("The caller lacks MANAGER_ROLE", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);

        await expect(connect(assetLiability, stranger).decreaseLiability([user.address], [BigInt(LIABILITY_AMOUNT)]))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AccessControlUnauthorizedAccount)
          .withArgs(stranger.address, ROLES.MANAGER_ROLE);
      });

      it("The account address is zero", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);

        await expect(connect(assetLiability, manager).decreaseLiability([ADDRESS_ZERO], [BigInt(LIABILITY_AMOUNT)]))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AccountAddressZero);
      });

      it("The amount is zero", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);

        await expect(connect(assetLiability, manager).decreaseLiability([user.address], [0]))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AmountZero);
      });

      it("The decrease amount exceeds current liability", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
        const initialAmount = BigInt(LIABILITY_AMOUNT);
        const excessAmount = initialAmount + 1n;
        const account = user.address;

        // First create a liability
        await proveTx(connect(assetLiability, manager).increaseLiability([account], [initialAmount]));

        // Try to decrease more than the current liability
        await expect(connect(assetLiability, manager).decreaseLiability([account], [excessAmount]))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_DecreaseAmountExcess);
      });

      it("The amount exceeds uint64 max", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
        const maxUint64 = maxUintForBits(64);
        const overflowAmount = maxUint64 + 1n;
        const initialAmount = BigInt(LIABILITY_AMOUNT) * 10n; // Create a valid initial liability
        const account = user.address;

        // First create a valid liability
        await proveTx(connect(assetLiability, manager).increaseLiability([account], [initialAmount]));

        // Now try to decrease with an amount that exceeds uint64 max
        await expect(connect(assetLiability, manager).decreaseLiability([account], [overflowAmount]))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.AssetLiability_AmountOverflow);
      });

      it("The contract is paused", async () => {
        const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
        const amount = BigInt(LIABILITY_AMOUNT);
        const account = user.address;

        // First create a liability
        await proveTx(connect(assetLiability, manager).increaseLiability([account], [amount]));

        // Pause the contract
        await pauseContract(assetLiability);

        // Try to decrease while paused
        await expect(connect(assetLiability, manager).decreaseLiability([account], [amount]))
          .to.be.revertedWithCustomError(assetLiability, ERRORS.EnforcedPause);
      });
    });
  });

  describe("View Functions", async () => {
    it("liabilityOf() returns correct amount", async () => {
      const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
      const amount = BigInt(LIABILITY_AMOUNT);
      const account = user.address;

      // Initially zero
      expect(await assetLiability.liabilityOf(account)).to.equal(0);

      // After increasing
      await proveTx(connect(assetLiability, manager).increaseLiability([account], [amount]));
      expect(await assetLiability.liabilityOf(account)).to.equal(amount);
    });

    it("totalLiability() returns correct total", async () => {
      const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
      const accounts = users.slice(0, 3).map(user => user.address);
      const amounts = LIABILITY_AMOUNTS.slice(0, 3).map(BigInt);
      const totalAmount = amounts.reduce((acc, val) => acc + val, 0n);

      // Initially zero
      expect(await assetLiability.totalLiability()).to.equal(0);

      // After increasing for multiple accounts
      await proveTx(connect(assetLiability, manager).increaseLiability(accounts, amounts));
      expect(await assetLiability.totalLiability()).to.equal(totalAmount);
    });

    it("underlyingToken() returns correct address", async () => {
      const { assetLiability, tokenMock } = await setUpFixture(deployAndConfigureContracts);
      expect(await assetLiability.underlyingToken()).to.equal(getAddress(tokenMock));
    });

    it("operationalTreasury() returns correct address", async () => {
      const { assetLiability } = await setUpFixture(deployAndConfigureContracts);
      expect(await assetLiability.operationalTreasury()).to.equal(treasury.address);
    });
  });
});
