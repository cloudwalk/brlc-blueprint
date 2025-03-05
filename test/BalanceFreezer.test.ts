import { ethers, network, upgrades } from "hardhat";
import { expect } from "chai";
import { Contract, ContractFactory } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { checkContractUupsUpgrading, connect, getAddress, proveTx } from "../test-utils/eth";

const ADDRESS_ZERO = ethers.ZeroAddress;

enum OperationStatus {
  Nonexistent = 0,
  TransferExecuted = 1,
  UpdateIncreaseExecuted = 2,
  UpdateDecreaseExecuted = 3,
  UpdateReplacementExecuted = 4
}

interface Version {
  major: number;
  minor: number;
  patch: number;

  [key: string]: number; // Indexing signature to ensure that fields are iterated over in a key-value style
}

interface Operation {
  status: OperationStatus;
  account: string;
  amount: bigint;

  // Indexing signature to ensure that fields are iterated over in a key-value style
  [key: string]: number | string | bigint;
}

interface TestOperation extends Operation {
  txId: string;
}

const defaultOperation: Operation = {
  status: OperationStatus.Nonexistent,
  account: ADDRESS_ZERO,
  amount: 0n
};

interface Fixture {
  freezerContract: Contract;
  tokenMock: Contract;
}

function checkEquality<T extends Record<string, unknown>>(actualObject: T, expectedObject: T, index?: number) {
  const indexString = !index ? "" : ` with index: ${index}`;
  Object.keys(expectedObject).forEach(property => {
    const value = actualObject[property];
    if (typeof value === "undefined" || typeof value === "function" || typeof value === "object") {
      throw Error(`Property "${property}" is not found in the actual object` + indexString);
    }
    expect(value).to.eq(
      expectedObject[property],
      `Mismatch in the "${property}" property between the actual object and expected one` + indexString
    );
  });
}

async function setUpFixture<T>(func: () => Promise<T>): Promise<T> {
  if (network.name === "hardhat") {
    return loadFixture(func);
  } else {
    return func();
  }
}

describe("Contracts 'BalanceFreezer'", async () => {
  const TX_ID_ARRAY: string[] = [
    ethers.encodeBytes32String("MOCK TX_ID 1"),
    ethers.encodeBytes32String("MOCK TX_ID 2"),
    ethers.encodeBytes32String("MOCK TX_ID 3"),
    ethers.encodeBytes32String("MOCK TX_ID 4"),
    ethers.encodeBytes32String("MOCK TX_ID 5")
  ];
  const TX_ID_ZERO = ethers.ZeroHash;
  const TOKEN_AMOUNT = 12345678;
  const TOKEN_AMOUNTS: number[] = [
    TOKEN_AMOUNT,
    TOKEN_AMOUNT * 2,
    TOKEN_AMOUNT * 3,
    TOKEN_AMOUNT * 4,
    TOKEN_AMOUNT * 5
  ];

  // Errors of the lib contracts
  const REVERT_ERROR_IF_CONTRACT_INITIALIZATION_IS_INVALID = "InvalidInitialization";
  const REVERT_ERROR_IF_CONTRACT_IS_NOT_INITIALIZING = "NotInitializing";
  const REVERT_ERROR_IF_CONTRACT_IS_PAUSED = "EnforcedPause";
  const REVERT_ERROR_IF_UNAUTHORIZED_ACCOUNT = "AccessControlUnauthorizedAccount";

  // Errors of the contracts under test
  const REVERT_ERROR_IF_AMOUNT_EXCESS = "BalanceFreezer_AmountExcess";
  const REVERT_ERROR_IF_IMPLEMENTATION_ADDRESS_INVALID = "BalanceFreezer_ImplementationAddressInvalid";
  const REVERT_ERROR_IF_OPERATION_ALREADY_EXECUTED = "BalanceFreezer_AlreadyExecuted";
  const REVERT_ERROR_IF_TOKEN_ADDRESS_IS_ZERO = "BalanceFreezer_TokenAddressZero";
  const REVERT_ERROR_IF_TX_ID_IS_ZERO = "BalanceFreezer_TxIdZero";

  // Events of the contracts under test
  const EVENT_NAME_FROZEN_BALANCE_TRANSFER = "FrozenBalanceTransfer";
  const EVENT_NAME_FROZEN_BALANCE_UPDATED = "FrozenBalanceUpdated";
  const EVENT_NAME_MOCK_CALL_FREEZE = "MockCallFreeze";
  const EVENT_NAME_MOCK_CALL_FREEZE_INCREASE = "MockCallFreezeIncrease";
  const EVENT_NAME_MOCK_CALL_FREEZE_DECREASE = "MockCallFreezeDecrease";
  const EVENT_NAME_MOCK_CALL_TRANSFER_FROZEN = "MockCallTransferFrozen";

  const EXPECTED_VERSION: Version = {
    major: 1,
    minor: 1,
    patch: 0
  };

  let freezerContractFactory: ContractFactory;
  let tokenMockFactory: ContractFactory;
  let deployer: HardhatEthersSigner;
  let freezer: HardhatEthersSigner;
  let receiver: HardhatEthersSigner;
  let user: HardhatEthersSigner;
  let users: HardhatEthersSigner[];

  const ownerRole: string = ethers.id("OWNER_ROLE");
  const pauserRole: string = ethers.id("PAUSER_ROLE");
  const rescuerRole: string = ethers.id("RESCUER_ROLE");
  const freezerRole: string = ethers.id("FREEZER_ROLE");

  before(async () => {
    let moreUsers: HardhatEthersSigner[];
    [deployer, freezer, receiver, user, ...moreUsers] = await ethers.getSigners();
    users = [user, ...moreUsers];

    // Contract factories with the explicitly specified deployer account
    freezerContractFactory = await ethers.getContractFactory("BalanceFreezerTestable");
    freezerContractFactory = freezerContractFactory.connect(deployer);
    tokenMockFactory = await ethers.getContractFactory("ERC20FreezableTokenMock");
    tokenMockFactory = tokenMockFactory.connect(deployer);
  });

  async function deployTokenMock(): Promise<Contract> {
    const name = "ERC20 Test";
    const symbol = "TEST";

    let tokenMock: Contract = await tokenMockFactory.deploy(name, symbol) as Contract;
    await tokenMock.waitForDeployment();
    tokenMock = connect(tokenMock, deployer); // Explicitly specifying the initial account

    return tokenMock;
  }

  async function deployContracts(): Promise<Fixture> {
    const tokenMock = await deployTokenMock();
    let freezerContract: Contract = await upgrades.deployProxy(
      freezerContractFactory,
      [getAddress(tokenMock)],
      { unsafeAllow: ["missing-initializer", "missing-initializer-call"] }
    ) as Contract;
    await freezerContract.waitForDeployment();
    freezerContract = connect(freezerContract, deployer); // Explicitly specifying the initial account

    return {
      freezerContract,
      tokenMock
    };
  }

  async function deployAndConfigureContracts(): Promise<Fixture> {
    const fixture = await deployContracts();
    const { freezerContract } = fixture;

    await proveTx(freezerContract.grantRole(freezerRole, freezer.address));

    return fixture;
  }

  function defineTestOperations(num: number = 1): TestOperation[] {
    const operations: TestOperation[] = [];
    const maxNum = Math.min(TX_ID_ARRAY.length, TOKEN_AMOUNTS.length, users.length);
    if (num > maxNum) {
      throw new Error(`The requested number of test operation structures is greater than ${maxNum}`);
    }
    for (let i = 0; i < num; ++i) {
      operations.push({
        txId: TX_ID_ARRAY[i],
        account: users[i].address,
        amount: BigInt(TOKEN_AMOUNTS[i]),
        status: OperationStatus.Nonexistent
      });
    }
    return operations;
  }

  async function pauseContract(contract: Contract) {
    await proveTx(contract.grantRole(pauserRole, deployer.address));
    await proveTx(contract.pause());
  }

  async function checkOperationStructureOnBlockchain(
    freezerContract: Contract,
    operation: TestOperation
  ) {
    const actualOperation: Record<string, unknown> = await freezerContract.getOperation(operation.txId);
    const expectedOperation: Operation = {
      status: operation.status,
      account: operation.account,
      amount: operation.amount
    };
    checkEquality(actualOperation, expectedOperation);
  }

  describe("Function 'initialize()'", async () => {
    it("Configures the contract as expected", async () => {
      const { freezerContract, tokenMock } = await setUpFixture(deployContracts);

      // The underlying token contract address
      expect(await freezerContract.underlyingToken()).to.equal(getAddress(tokenMock));

      // Role hashes
      expect(await freezerContract.OWNER_ROLE()).to.equal(ownerRole);
      expect(await freezerContract.PAUSER_ROLE()).to.equal(pauserRole);
      expect(await freezerContract.RESCUER_ROLE()).to.equal(rescuerRole);
      expect(await freezerContract.FREEZER_ROLE()).to.equal(freezerRole);

      // The role admins
      expect(await freezerContract.getRoleAdmin(ownerRole)).to.equal(ownerRole);
      expect(await freezerContract.getRoleAdmin(pauserRole)).to.equal(ownerRole);
      expect(await freezerContract.getRoleAdmin(rescuerRole)).to.equal(ownerRole);
      expect(await freezerContract.getRoleAdmin(freezerRole)).to.equal(ownerRole);

      // The deployer should have the owner role, but not the other roles
      expect(await freezerContract.hasRole(ownerRole, deployer.address)).to.equal(true);
      expect(await freezerContract.hasRole(pauserRole, deployer.address)).to.equal(false);
      expect(await freezerContract.hasRole(rescuerRole, deployer.address)).to.equal(false);
      expect(await freezerContract.hasRole(freezerRole, deployer.address)).to.equal(false);

      // The initial contract state is unpaused
      expect(await freezerContract.paused()).to.equal(false);
    });

    it("Is reverted if it is called a second time", async () => {
      const { freezerContract, tokenMock } = await setUpFixture(deployContracts);
      await expect(
        freezerContract.initialize(getAddress(tokenMock))
      ).to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_CONTRACT_INITIALIZATION_IS_INVALID);
    });

    it("Is reverted if the passed token address is zero", async () => {
      const anotherFreezerContract: Contract = await upgrades.deployProxy(
        freezerContractFactory,
        [],
        { initializer: false, unsafeAllow: ["missing-initializer", "missing-initializer-call"] },
      ) as Contract;

      await expect(
        anotherFreezerContract.initialize(ADDRESS_ZERO)
      ).to.be.revertedWithCustomError(freezerContractFactory, REVERT_ERROR_IF_TOKEN_ADDRESS_IS_ZERO);
    });

    it("Is reverted if the internal initializer is called outside the init process", async () => {
      const { freezerContract, tokenMock } = await setUpFixture(deployContracts);
      await expect(
        freezerContract.call_parent_initialize(getAddress(tokenMock))
      ).to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_CONTRACT_IS_NOT_INITIALIZING);
    });

    it("Is reverted if the unchained internal initializer is called outside the init process", async () => {
      const { freezerContract, tokenMock } = await setUpFixture(deployContracts);
      await expect(
        freezerContract.call_parent_initialize_unchained(getAddress(tokenMock))
      ).to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_CONTRACT_IS_NOT_INITIALIZING);
    });
  });

  describe("Function 'upgradeToAndCall()'", async () => {
    it("Executes as expected", async () => {
      const { freezerContract } = await setUpFixture(deployContracts);
      await checkContractUupsUpgrading(freezerContract, freezerContractFactory);
    });

    it("Is reverted if the caller does not have the owner role", async () => {
      const { freezerContract } = await setUpFixture(deployContracts);

      await expect(connect(freezerContract, user).upgradeToAndCall(getAddress(freezerContract), "0x"))
        .to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_UNAUTHORIZED_ACCOUNT)
        .withArgs(user.address, ownerRole);
    });
  });

  describe("Function 'upgradeTo()'", async () => {
    it("Executes as expected", async () => {
      const { freezerContract } = await setUpFixture(deployContracts);
      await checkContractUupsUpgrading(freezerContract, freezerContractFactory, "upgradeTo(address)");
    });

    it("Is reverted if the caller does not have the owner role", async () => {
      const { freezerContract } = await setUpFixture(deployContracts);

      await expect(connect(freezerContract, user).upgradeTo(getAddress(freezerContract)))
        .to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_UNAUTHORIZED_ACCOUNT)
        .withArgs(user.address, ownerRole);
    });

    it("Is reverted if the provided implementation address is not a balance freezer contract", async () => {
      const { freezerContract, tokenMock } = await setUpFixture(deployContracts);

      await expect(freezerContract.upgradeTo(getAddress(tokenMock)))
        .to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_IMPLEMENTATION_ADDRESS_INVALID);
    });
  });

  describe("Function 'freeze()'", async () => {
    async function executeAndCheckFreezing(fixture: Fixture, operation: TestOperation) {
      const { freezerContract, tokenMock } = fixture;
      const oldFrozenBalance = await tokenMock.OLD_FROZEN_BALANCE_MOCK();
      const newFrozenBalance: bigint = operation.amount;

      const operationBefore: TestOperation = { txId: operation.txId, ...defaultOperation };
      await checkOperationStructureOnBlockchain(freezerContract, operationBefore);

      const tx = connect(freezerContract, freezer).freeze(
        operation.account,
        operation.amount,
        operation.txId
      );
      await expect(tx).to.be.emit(freezerContract, EVENT_NAME_FROZEN_BALANCE_UPDATED).withArgs(
        operation.account,
        newFrozenBalance,
        oldFrozenBalance,
        operation.txId
      );
      await expect(tx).to.be.emit(tokenMock, EVENT_NAME_MOCK_CALL_FREEZE).withArgs(
        operation.account,
        operation.amount
      );

      operation.status = OperationStatus.UpdateReplacementExecuted;
      await checkOperationStructureOnBlockchain(freezerContract, operation);
    }

    it("Executes as expected with different account address and amount values", async () => {
      const fixture = await setUpFixture(deployAndConfigureContracts);
      const operations: TestOperation[] = defineTestOperations(3);
      operations[1].amount = 0n;

      // This is allowed in the contract under test, but not for the real token contract
      operations[2].account = ADDRESS_ZERO;

      await executeAndCheckFreezing(fixture, operations[0]);
      await executeAndCheckFreezing(fixture, operations[1]);
      await executeAndCheckFreezing(fixture, operations[2]);
    });

    it("Is reverted if the contract is paused", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      await pauseContract(freezerContract);
      await expect(connect(freezerContract, freezer).freeze(operation.account, operation.amount, operation.txId))
        .to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_CONTRACT_IS_PAUSED);
    });

    it("Is reverted if the caller does not have the freezer role", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      await expect(connect(freezerContract, deployer).freeze(operation.account, operation.amount, operation.txId))
        .to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_UNAUTHORIZED_ACCOUNT)
        .withArgs(deployer.address, freezerRole);
    });

    it("Is reverted if the provided off-chain transaction identifier is zero", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      operation.txId = TX_ID_ZERO;
      await expect(connect(freezerContract, freezer).freeze(operation.account, operation.amount, operation.txId))
        .to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_TX_ID_IS_ZERO);
    });

    it("Is reverted if the provided amount is greater than 64-bit unsigned integer", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      operation.amount = BigInt(2) ** 64n;
      await expect(connect(freezerContract, freezer).freeze(operation.account, operation.amount, operation.txId))
        .to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_AMOUNT_EXCESS)
        .withArgs(operation.amount);
    });

    it("Is reverted if an operation with the provided ID has been already executed", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      await proveTx(connect(freezerContract, freezer).freeze(operation.account, operation.amount, operation.txId));
      await expect(connect(freezerContract, freezer).freeze(operation.account, operation.amount, operation.txId))
        .to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_OPERATION_ALREADY_EXECUTED)
        .withArgs(operation.txId);
    });
  });

  describe("Function 'freezeIncrease()'", async () => {
    async function executeAndCheckFreezeIncreasing(fixture: Fixture, operation: TestOperation) {
      const { freezerContract, tokenMock } = fixture;
      const oldFrozenBalance = await tokenMock.OLD_FROZEN_BALANCE_MOCK();
      const newFrozenBalance = oldFrozenBalance + operation.amount;

      const operationBefore: TestOperation = { txId: operation.txId, ...defaultOperation };
      await checkOperationStructureOnBlockchain(freezerContract, operationBefore);

      const tx = connect(freezerContract, freezer).freezeIncrease(
        operation.account,
        operation.amount,
        operation.txId
      );
      await expect(tx).to.be.emit(freezerContract, EVENT_NAME_FROZEN_BALANCE_UPDATED).withArgs(
        operation.account,
        newFrozenBalance,
        oldFrozenBalance,
        operation.txId
      );
      await expect(tx).to.be.emit(tokenMock, EVENT_NAME_MOCK_CALL_FREEZE_INCREASE).withArgs(
        operation.account,
        operation.amount
      );

      operation.status = OperationStatus.UpdateIncreaseExecuted;
      await checkOperationStructureOnBlockchain(freezerContract, operation);
    }

    it("Executes as expected with different account address and amount values", async () => {
      const fixture = await setUpFixture(deployAndConfigureContracts);
      const operations: TestOperation[] = defineTestOperations(3);

      // This following cases are allowed in the contract under test, but not for the real token contract
      operations[1].amount = 0n;
      operations[2].account = ADDRESS_ZERO;

      await executeAndCheckFreezeIncreasing(fixture, operations[0]);
      await executeAndCheckFreezeIncreasing(fixture, operations[1]);
      await executeAndCheckFreezeIncreasing(fixture, operations[2]);
    });

    it("Is reverted if the contract is paused", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      await pauseContract(freezerContract);
      await expect(
        connect(freezerContract, freezer).freezeIncrease(operation.account, operation.amount, operation.txId)
      ).to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_CONTRACT_IS_PAUSED);
    });

    it("Is reverted if the caller does not have the freezer role", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      await expect(
        connect(freezerContract, deployer).freezeIncrease(operation.account, operation.amount, operation.txId)
      ).to.be.revertedWithCustomError(
        freezerContract,
        REVERT_ERROR_IF_UNAUTHORIZED_ACCOUNT
      ).withArgs(deployer.address, freezerRole);
    });

    it("Is reverted if the provided off-chain transaction identifier is zero", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      operation.txId = TX_ID_ZERO;
      await expect(
        connect(freezerContract, freezer).freezeIncrease(operation.account, operation.amount, operation.txId)
      ).to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_TX_ID_IS_ZERO);
    });

    it("Is reverted if the provided amount is greater than 64-bit unsigned integer", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      operation.amount = BigInt(2) ** 64n;
      await expect(
        connect(freezerContract, freezer).freezeIncrease(operation.account, operation.amount, operation.txId)
      ).to.be.revertedWithCustomError(
        freezerContract,
        REVERT_ERROR_IF_AMOUNT_EXCESS
      ).withArgs(operation.amount);
    });

    it("Is reverted if an operation with the provided ID has been already executed", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      await proveTx(connect(freezerContract, freezer).freeze(operation.account, operation.amount, operation.txId));
      await expect(
        connect(freezerContract, freezer).freezeIncrease(operation.account, operation.amount, operation.txId)
      ).to.be.revertedWithCustomError(
        freezerContract,
        REVERT_ERROR_IF_OPERATION_ALREADY_EXECUTED
      ).withArgs(operation.txId);
    });
  });

  describe("Function 'freezeDecrease()'", async () => {
    async function executeAndCheckFreezeDecreasing(fixture: Fixture, operation: TestOperation) {
      const { freezerContract, tokenMock } = fixture;
      const oldFrozenBalance = await tokenMock.OLD_FROZEN_BALANCE_MOCK();
      const newFrozenBalance = (operation.amount > oldFrozenBalance) ? 0n : oldFrozenBalance - operation.amount;

      const operationBefore: TestOperation = { txId: operation.txId, ...defaultOperation };
      await checkOperationStructureOnBlockchain(freezerContract, operationBefore);

      const tx = connect(freezerContract, freezer).freezeDecrease(
        operation.account,
        operation.amount,
        operation.txId
      );
      await expect(tx).to.be.emit(freezerContract, EVENT_NAME_FROZEN_BALANCE_UPDATED).withArgs(
        operation.account,
        newFrozenBalance,
        oldFrozenBalance,
        operation.txId
      );
      await expect(tx).to.be.emit(tokenMock, EVENT_NAME_MOCK_CALL_FREEZE_DECREASE).withArgs(
        operation.account,
        operation.amount
      );

      operation.status = OperationStatus.UpdateDecreaseExecuted;
      await checkOperationStructureOnBlockchain(freezerContract, operation);
    }

    it("Executes as expected with different account address and amount values", async () => {
      const fixture = await setUpFixture(deployAndConfigureContracts);
      const operations: TestOperation[] = defineTestOperations(4);
      const oldFrozenBalance: bigint = await fixture.tokenMock.OLD_FROZEN_BALANCE_MOCK();

      // This following cases are allowed in the contract under test, but not for the real token contract
      operations[1].amount = 0n;
      operations[2].amount = oldFrozenBalance + 1n;
      operations[3].account = ADDRESS_ZERO;

      await executeAndCheckFreezeDecreasing(fixture, operations[0]);
      await executeAndCheckFreezeDecreasing(fixture, operations[1]);
      await executeAndCheckFreezeDecreasing(fixture, operations[2]);
      await executeAndCheckFreezeDecreasing(fixture, operations[3]);
    });

    it("Is reverted if the contract is paused", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      await pauseContract(freezerContract);
      await expect(
        connect(freezerContract, freezer).freezeDecrease(operation.account, operation.amount, operation.txId)
      ).to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_CONTRACT_IS_PAUSED);
    });

    it("Is reverted if the caller does not have the freezer role", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      await expect(
        connect(freezerContract, deployer).freezeDecrease(operation.account, operation.amount, operation.txId)
      ).to.be.revertedWithCustomError(
        freezerContract,
        REVERT_ERROR_IF_UNAUTHORIZED_ACCOUNT
      ).withArgs(deployer.address, freezerRole);
    });

    it("Is reverted if the provided off-chain transaction identifier is zero", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      operation.txId = TX_ID_ZERO;
      await expect(
        connect(freezerContract, freezer).freezeDecrease(operation.account, operation.amount, operation.txId)
      ).to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_TX_ID_IS_ZERO);
    });

    it("Is reverted if the provided amount is greater than 64-bit unsigned integer", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      operation.amount = BigInt(2) ** 64n;
      await expect(
        connect(freezerContract, freezer).freezeDecrease(operation.account, operation.amount, operation.txId)
      ).to.be.revertedWithCustomError(
        freezerContract,
        REVERT_ERROR_IF_AMOUNT_EXCESS
      ).withArgs(operation.amount);
    });

    it("Is reverted if an operation with the provided ID has been already executed", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      await proveTx(connect(freezerContract, freezer).freeze(operation.account, operation.amount, operation.txId));
      await expect(
        connect(freezerContract, freezer).freezeDecrease(operation.account, operation.amount, operation.txId)
      ).to.be.revertedWithCustomError(
        freezerContract,
        REVERT_ERROR_IF_OPERATION_ALREADY_EXECUTED
      ).withArgs(operation.txId);
    });
  });

  describe("Function 'transferFrozen()' accompanied by the 'registerOperation()' one", async () => {
    async function executeAndCheckTransferring(
      fixture: Fixture,
      operation: TestOperation,
      receiverAddress: string
    ) {
      const { freezerContract, tokenMock } = fixture;
      const oldFrozenBalance = await tokenMock.OLD_FROZEN_BALANCE_MOCK();
      const newFrozenBalance = (operation.amount > oldFrozenBalance) ? 0n : oldFrozenBalance - operation.amount;

      const operationBefore: TestOperation = { txId: operation.txId, ...defaultOperation };
      await checkOperationStructureOnBlockchain(freezerContract, operationBefore);

      const tx = connect(freezerContract, freezer).transferFrozen(
        operation.account, // from
        receiverAddress, // to
        operation.amount,
        operation.txId
      );
      await expect(tx).to.be.emit(freezerContract, EVENT_NAME_FROZEN_BALANCE_TRANSFER).withArgs(
        operation.account,
        operation.amount,
        operation.txId,
        receiverAddress
      );
      await expect(tx).to.be.emit(freezerContract, EVENT_NAME_FROZEN_BALANCE_UPDATED).withArgs(
        operation.account,
        newFrozenBalance,
        oldFrozenBalance,
        operation.txId
      );
      expect(tx).to.be.emit(tokenMock, EVENT_NAME_MOCK_CALL_TRANSFER_FROZEN).withArgs(
        operation.account, // from
        receiverAddress, // to
        operation.amount
      );

      operation.status = OperationStatus.TransferExecuted;
      await checkOperationStructureOnBlockchain(freezerContract, operation);
    }

    it("Executes as expected with different account address and amount values", async () => {
      const fixture = await setUpFixture(deployAndConfigureContracts);
      const operations: TestOperation[] = defineTestOperations(5);
      const oldFrozenBalance: bigint = await fixture.tokenMock.OLD_FROZEN_BALANCE_MOCK();
      const receiverAddresses: string[] = Array(operations.length).fill(receiver.address);

      operations[1].amount = 0n;
      // This following cases are allowed in the contract under test, but not for the real token contract
      operations[2].amount = oldFrozenBalance + 1n;
      operations[3].account = ADDRESS_ZERO;
      receiverAddresses[4] = ADDRESS_ZERO;

      await executeAndCheckTransferring(fixture, operations[0], receiverAddresses[0]);
      await executeAndCheckTransferring(fixture, operations[1], receiverAddresses[1]);
      await executeAndCheckTransferring(fixture, operations[2], receiverAddresses[2]);
      await executeAndCheckTransferring(fixture, operations[3], receiverAddresses[3]);
      await executeAndCheckTransferring(fixture, operations[4], receiverAddresses[4]);
    });

    it("Is reverted if the contract is paused", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      await pauseContract(freezerContract);
      await expect(connect(freezerContract, freezer).transferFrozen(
        operation.account, // from
        receiver.address, // to
        operation.amount,
        operation.txId
      )).to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_CONTRACT_IS_PAUSED);
    });

    it("Is reverted if the caller does not have the freezer role", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      await expect(connect(freezerContract, deployer).transferFrozen(
        operation.account, // from
        receiver.address, // to
        operation.amount,
        operation.txId
      )).to.be.revertedWithCustomError(
        freezerContract,
        REVERT_ERROR_IF_UNAUTHORIZED_ACCOUNT
      ).withArgs(deployer.address, freezerRole);
    });

    it("Is reverted if the provided off-chain transaction identifier is zero", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      operation.txId = TX_ID_ZERO;
      await expect(connect(freezerContract, freezer).transferFrozen(
        operation.account, // from
        receiver.address, // to
        operation.amount,
        operation.txId
      )).to.be.revertedWithCustomError(freezerContract, REVERT_ERROR_IF_TX_ID_IS_ZERO);
    });

    it("Is reverted if the provided amount is greater than 64-bit unsigned integer", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      operation.amount = BigInt(2) ** 64n;
      await expect(connect(freezerContract, freezer).transferFrozen(
        operation.account, // from
        receiver.address, // to
        operation.amount,
        operation.txId
      )).to.be.revertedWithCustomError(
        freezerContract,
        REVERT_ERROR_IF_AMOUNT_EXCESS
      ).withArgs(operation.amount);
    });

    it("Is reverted if an operation with the provided ID has been already executed", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const [operation] = defineTestOperations();
      await proveTx(connect(freezerContract, freezer).freeze(operation.account, operation.amount, operation.txId));
      await expect(connect(freezerContract, freezer).transferFrozen(
        operation.account, // from
        receiver.address, // to
        operation.amount,
        operation.txId
      )).to.be.revertedWithCustomError(
        freezerContract,
        REVERT_ERROR_IF_OPERATION_ALREADY_EXECUTED
      ).withArgs(operation.txId);
    });
  });

  describe("Function 'balanceOfFrozen()'", async () => {
    it("Executes as expected", async () => {
      const { freezerContract, tokenMock } = await setUpFixture(deployAndConfigureContracts);
      const expectedBalance: bigint = BigInt(await tokenMock.OLD_FROZEN_BALANCE_MOCK()) + BigInt(user.address);
      const actualBalance = await freezerContract.balanceOfFrozen(user.address);
      expect(actualBalance).to.equal(expectedBalance);
    });
  });

  describe("Function '$__VERSION()'", async () => {
    it("Returns expected values", async () => {
      const { freezerContract } = await setUpFixture(deployAndConfigureContracts);
      const tokenVersion = await freezerContract.$__VERSION();
      checkEquality(tokenVersion, EXPECTED_VERSION);
    });
  });
});
