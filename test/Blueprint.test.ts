import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import { Contract, ContractFactory } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { checkContractUupsUpgrading, connect, getAddress, proveTx } from "../test-utils/eth";
import { checkEquality, setUpFixture } from "../test-utils/common";

const ADDRESS_ZERO = ethers.ZeroAddress;

enum OperationStatus {
  Nonexistent = 0,
  Deposit = 1,
  Withdrawal = 2
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
  opId: string;
}

const defaultOperation: Operation = {
  status: OperationStatus.Nonexistent,
  account: ADDRESS_ZERO,
  amount: 0n
};

interface Fixture {
  blueprint: Contract;
  tokenMock: Contract;
}

describe("Contracts 'Blueprint'", async () => {
  const OP_ID_ARRAY: string[] = [
    ethers.encodeBytes32String("MOCK OP_ID 1"),
    ethers.encodeBytes32String("MOCK OP_ID 2"),
    ethers.encodeBytes32String("MOCK OP_ID 3"),
    ethers.encodeBytes32String("MOCK OP_ID 4"),
    ethers.encodeBytes32String("MOCK OP_ID 5")
  ];
  const OP_ID_ZERO = ethers.ZeroHash;
  const TOKEN_AMOUNT = 12345678;
  const TOKEN_AMOUNTS: number[] = [
    TOKEN_AMOUNT,
    TOKEN_AMOUNT * 2,
    TOKEN_AMOUNT * 3,
    TOKEN_AMOUNT * 4,
    TOKEN_AMOUNT * 5
  ];

  // Errors of the lib contracts
  const ERROR_NAME_CONTRACT_INITIALIZATION_IS_INVALID = "InvalidInitialization";
  const ERROR_NAME_CONTRACT_IS_PAUSED = "EnforcedPause";
  const ERROR_NAME_UNAUTHORIZED_ACCOUNT = "AccessControlUnauthorizedAccount";

  // Errors of the contracts under test
  const ERROR_NAME_IMPLEMENTATION_ADDRESS_INVALID = "Blueprint_ImplementationAddressInvalid";
  const ERROR_NAME_TOKEN_ADDRESS_IS_ZERO = "Blueprint_TokenAddressZero";

  // Events of the contracts under test
  const EVENT_NAME_BALANCE_UPDATED = "BalanceUpdated";
  const EVENT_NAME_UNDERLYING_TOKEN_CHANGED = "UnderlyingTokenChanged";
  const EVENT_NAME_OPERATIONAL_TREASURY_CHANGED = "OperationalTreasuryChanged";

  const EXPECTED_VERSION: Version = {
    major: 1,
    minor: 0,
    patch: 0
  };

  let blueprintFactory: ContractFactory;
  let deployer: HardhatEthersSigner;
  let manager: HardhatEthersSigner;
  let treasury: HardhatEthersSigner;
  let user: HardhatEthersSigner;
  let users: HardhatEthersSigner[];

  const OWNER_ROLE: string = ethers.id("OWNER_ROLE");
  const PAUSER_ROLE: string = ethers.id("PAUSER_ROLE");
  const RESCUER_ROLE: string = ethers.id("RESCUER_ROLE");
  const MANAGER_ROLE: string = ethers.id("MANAGER_ROLE");

  before(async () => {
    let moreUsers: HardhatEthersSigner[];
    [deployer, manager, treasury, user, ...moreUsers] = await ethers.getSigners();
    users = [user, ...moreUsers];

    // The contract factories with the explicitly specified deployer account
    blueprintFactory = await ethers.getContractFactory("Blueprint");
    blueprintFactory = blueprintFactory.connect(deployer);
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
    let blueprint: Contract = await upgrades.deployProxy(blueprintFactory, [getAddress(tokenMock)]) as Contract;
    await blueprint.waitForDeployment();
    blueprint = connect(blueprint, deployer); // Explicitly specifying the initial account

    return {
      blueprint,
      tokenMock
    };
  }

  async function deployAndConfigureContracts(): Promise<Fixture> {
    const fixture = await deployContracts();
    const { blueprint } = fixture;

    await proveTx(blueprint.grantRole(MANAGER_ROLE, manager.address));

    return fixture;
  }

  function defineTestOperations(num: number = 1): TestOperation[] {
    const operations: TestOperation[] = [];
    const maxNum = Math.min(OP_ID_ARRAY.length, TOKEN_AMOUNTS.length, users.length);
    if (num > maxNum) {
      throw new Error(`The requested number of test operation structures is greater than ${maxNum}`);
    }
    for (let i = 0; i < num; ++i) {
      operations.push({
        opId: OP_ID_ARRAY[i],
        account: users[i].address,
        amount: BigInt(TOKEN_AMOUNTS[i]),
        status: OperationStatus.Nonexistent
      });
    }
    return operations;
  }

  async function pauseContract(contract: Contract) {
    await proveTx(contract.grantRole(PAUSER_ROLE, deployer.address));
    await proveTx(contract.pause());
  }

  async function checkOperationStructureOnBlockchain(
    blueprint: Contract,
    operation: TestOperation
  ) {
    const actualOperation: Record<string, unknown> = await blueprint.getOperation(operation.opId);
    const expectedOperation: Operation = {
      status: operation.status,
      account: operation.account,
      amount: operation.amount
    };
    checkEquality(actualOperation, expectedOperation);
  }

  describe("Function 'initialize()'", async () => {
    it("Configures the contract as expected and emits the correct event", async () => {
      const { blueprint, tokenMock } = await setUpFixture(deployContracts);

      // The underlying token contract address
      expect(await blueprint.underlyingToken()).to.equal(getAddress(tokenMock));

      // Role hashes
      expect(await blueprint.OWNER_ROLE()).to.equal(OWNER_ROLE);
      expect(await blueprint.PAUSER_ROLE()).to.equal(PAUSER_ROLE);
      expect(await blueprint.RESCUER_ROLE()).to.equal(RESCUER_ROLE);
      expect(await blueprint.MANAGER_ROLE()).to.equal(MANAGER_ROLE);

      // The role admins
      expect(await blueprint.getRoleAdmin(OWNER_ROLE)).to.equal(OWNER_ROLE);
      expect(await blueprint.getRoleAdmin(PAUSER_ROLE)).to.equal(OWNER_ROLE);
      expect(await blueprint.getRoleAdmin(RESCUER_ROLE)).to.equal(OWNER_ROLE);
      expect(await blueprint.getRoleAdmin(MANAGER_ROLE)).to.equal(OWNER_ROLE);

      // The deployer should have the owner role, but not the other roles
      expect(await blueprint.hasRole(OWNER_ROLE, deployer.address)).to.equal(true);
      expect(await blueprint.hasRole(PAUSER_ROLE, deployer.address)).to.equal(false);
      expect(await blueprint.hasRole(RESCUER_ROLE, deployer.address)).to.equal(false);
      expect(await blueprint.hasRole(MANAGER_ROLE, deployer.address)).to.equal(false);

      // The initial contract state is unpaused
      expect(await blueprint.paused()).to.equal(false);
    });

    it("Is reverted if it is called a second time", async () => {
      const { blueprint, tokenMock } = await setUpFixture(deployContracts);
      await expect(
        blueprint.initialize(getAddress(tokenMock))
      ).to.be.revertedWithCustomError(blueprint, ERROR_NAME_CONTRACT_INITIALIZATION_IS_INVALID);
    });

    it("Is reverted if the passed token address is zero", async () => {
      const anotherFreezerContract: Contract = await upgrades.deployProxy(
        blueprintFactory,
        [],
        { initializer: false }
      ) as Contract;

      await expect(
        anotherFreezerContract.initialize(ADDRESS_ZERO)
      ).to.be.revertedWithCustomError(blueprintFactory, ERROR_NAME_TOKEN_ADDRESS_IS_ZERO);
    });
  });

  describe("Function 'upgradeToAndCall()'", async () => {
    it("Executes as expected", async () => {
      const { blueprint } = await setUpFixture(deployContracts);
      await checkContractUupsUpgrading(blueprint, blueprintFactory);
    });

    it("Is reverted if the caller does not have the owner role", async () => {
      const { blueprint } = await setUpFixture(deployContracts);

      await expect(connect(blueprint, user).upgradeToAndCall(getAddress(blueprint), "0x"))
        .to.be.revertedWithCustomError(blueprint, ERROR_NAME_UNAUTHORIZED_ACCOUNT)
        .withArgs(user.address, OWNER_ROLE);
    });

    it("Is reverted if the caller does not have the owner role", async () => {
      const { blueprint } = await setUpFixture(deployContracts);

      await expect(connect(blueprint, user).upgradeToAndCall(getAddress(blueprint), "0x"))
        .to.be.revertedWithCustomError(blueprint, ERROR_NAME_UNAUTHORIZED_ACCOUNT)
        .withArgs(user.address, OWNER_ROLE);
    });

    it("Is reverted if the provided implementation address does not belong to a blueprint contract", async () => {
      const { blueprint, tokenMock } = await setUpFixture(deployContracts);

      await expect(blueprint.upgradeToAndCall(getAddress(tokenMock), "0x"))
        .to.be.revertedWithCustomError(blueprint, ERROR_NAME_IMPLEMENTATION_ADDRESS_INVALID);
    });
  });

  describe("Function '$__VERSION()'", async () => {
    it("Returns expected values", async () => {
      const { blueprint } = await setUpFixture(deployAndConfigureContracts);
      const tokenVersion = await blueprint.$__VERSION();
      checkEquality(tokenVersion, EXPECTED_VERSION);
    });
  });
});
