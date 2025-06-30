import { ethers, upgrades } from "hardhat";
import { expect } from "chai";
import { Contract, ContractFactory } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { checkContractUupsUpgrading, connect, getAddress, proveTx } from "../test-utils/eth";
import { checkEquality, setUpFixture } from "../test-utils/common";

const ADDRESS_ZERO = ethers.ZeroAddress;
const ALLOWANCE_MAX = ethers.MaxUint256;
const BALANCE_INITIAL = 1000_000_000_000n;

const OWNER_ROLE: string = ethers.id("OWNER_ROLE");
const GRANTOR_ROLE: string = ethers.id("GRANTOR_ROLE");
const PAUSER_ROLE: string = ethers.id("PAUSER_ROLE");
const RESCUER_ROLE: string = ethers.id("RESCUER_ROLE");
const ADMIN_ROLE: string = ethers.id("ADMIN_ROLE");

// Events of the contract under test
const EVENT_NAME_WALLET_CREATED = "WalletCreated";
const EVENT_NAME_WALLET_DEACTIVATED = "WalletDeactivated";
const EVENT_NAME_WALLET_ACTIVATED = "WalletActivated";
const EVENT_NAME_WALLET_REMOVED = "WalletRemoved";
const EVENT_NAME_PARTICIPANT_ADDED = "ParticipantAdded";
const EVENT_NAME_PARTICIPANT_REMOVED = "ParticipantRemoved";
const EVENT_NAME_DEPOSIT = "Deposit";
const EVENT_NAME_WITHDRAWAL = "Withdrawal";
const EVENT_NAME_TRANSFER_IN = "TransferIn";
const EVENT_NAME_TRANSFER_OUT = "TransferOut";

// Errors of the library contracts
const ERROR_NAME_ACCESS_CONTROL_UNAUTHORIZED_ACCOUNT = "AccessControlUnauthorizedAccount";
const ERROR_NAME_ENFORCED_PAUSE = "EnforcedPause";
const ERROR_NAME_INVALID_INITIALIZATION = "InvalidInitialization";

// Errors of the contract under test
const ERROR_NAME_AGGREGATED_BALANCE_EXCESS = "SharedWalletController_AggregatedBalanceExcess";
const ERROR_NAME_IMPLEMENTATION_ADDRESS_INVALID = "SharedWalletController_ImplementationAddressInvalid";
const ERROR_NAME_PARTICIPANT_ADDRESS_ZERO = "SharedWalletController_ParticipantAddressZero";
const ERROR_NAME_PARTICIPANT_ARRAY_EMPTY = "SharedWalletController_ParticipantArrayEmpty";
const ERROR_NAME_PARTICIPANT_BALANCE_INSUFFICIENT = "SharedWalletController_ParticipantBalanceInsufficient";
const ERROR_NAME_PARTICIPANT_BALANCE_NONZERO = "SharedWalletController_ParticipantBalanceNonzero";
const ERROR_NAME_PARTICIPANT_COUNT_EXCESS = "SharedWalletController_ParticipantCountExcess";
const ERROR_NAME_PARTICIPANT_NON_REGISTERED = "SharedWalletController_ParticipantNonRegistered";
const ERROR_NAME_PARTICIPANT_REGISTERED_ALREADY = "SharedWalletController_ParticipantRegisteredAlready";
const ERROR_NAME_PARTICIPANT_IS_SHARED_WALLET = "SharedWalletController_ParticipantIsSharedWallet";
const ERROR_NAME_PARTICIPANT_UNREMOVABLE = "SharedWalletController_ParticipantUnremovable";
const ERROR_NAME_SHARES_CALCULATION_INCORRECT = "SharedWalletController_SharesCalculationIncorrect";
const ERROR_NAME_TOKEN_UNAUTHORIZED = "SharedWalletController_TokenUnauthorized";
const ERROR_NAME_WALLET_ADDRESS_ZERO = "SharedWalletController_WalletAddressZero";
const ERROR_NAME_WALLET_COUNT_EXCESS = "SharedWalletController_WalletCountExcess";
const ERROR_NAME_WALLET_EXISTENT_ALREADY = "SharedWalletController_WalletExistentAlready";
const ERROR_NAME_WALLET_BALANCE_INSUFFICIENT = "SharedWalletController_WalletBalanceInsufficient";
const ERROR_NAME_WALLET_BALANCE_NONZERO = "SharedWalletController_WalletBalanceNonzero";
const ERROR_NAME_WALLET_NONEXISTENT = "SharedWalletController_WalletNonexistent";
const ERROR_NAME_WALLET_PARTICIPANT_ADDRESSES_BOTH_ZERO = "SharedWalletController_WalletParticipantAddressesBothZero";
const ERROR_NAME_WALLET_STATUS_INCOMPATIBLE = "SharedWalletController_WalletStatusIncompatible";

enum WalletStatus {
  Nonexistent = 0,
  Active = 1,
  Deactivated = 2
}

enum ParticipantStatus {
  NonRegistered = 0,
  Registered = 1
}

interface ParticipantStateView {
  wallet: string;
  participant: string;
  status: ParticipantStatus;
  index: bigint;
  balance: bigint;

  [key: string]: string | number | bigint;
}

interface WalletParticipantPair {
  wallet: string;
  participant: string;
}

interface Fixture {
  sharedWalletController: Contract;
  tokenMock: Contract;
}

const defaultParticipantStateView: ParticipantStateView = {
  wallet: ADDRESS_ZERO,
  status: ParticipantStatus.NonRegistered,
  index: 0,
  participant: ADDRESS_ZERO,
  balance: 0n
};

describe("Contract 'SharedWalletController'", async () => {
  let sharedWalletControllerFactory: ContractFactory;

  let deployer: HardhatEthersSigner;
  let admin: HardhatEthersSigner;
  let stranger: HardhatEthersSigner;
  let sharedWallets: HardhatEthersSigner[];
  let participants: HardhatEthersSigner[];

  before(async () => {
    let wallet1: HardhatEthersSigner;
    let wallet2: HardhatEthersSigner;
    let participant1: HardhatEthersSigner;
    let participant2: HardhatEthersSigner;
    let participant3: HardhatEthersSigner;

    [deployer, admin, stranger, wallet1, wallet2, participant1, participant2, participant3] = await ethers.getSigners();
    sharedWallets = [wallet1, wallet2];
    participants = [participant1, participant2, participant3];

    sharedWalletControllerFactory = await ethers.getContractFactory("SharedWalletControllerTestable");
    sharedWalletControllerFactory = sharedWalletControllerFactory.connect(deployer);
  });

  async function deployTokenMock(): Promise<Contract> {
    const name = "ERC20 Test";
    const symbol = "TEST";

    let tokenMockFactory = await ethers.getContractFactory("ERC20TokenMockWithHooks");
    tokenMockFactory = tokenMockFactory.connect(deployer);

    let tokenMock = await tokenMockFactory.deploy(name, symbol) as Contract;
    await tokenMock.waitForDeployment();
    tokenMock = connect(tokenMock, deployer);

    return tokenMock;
  }

  async function deployContracts(): Promise<Fixture> {
    const tokenMock = await deployTokenMock();
    let sharedWalletController = await upgrades.deployProxy(
      sharedWalletControllerFactory,
      [getAddress(tokenMock)]
    ) as Contract;
    await sharedWalletController.waitForDeployment();
    sharedWalletController = connect(sharedWalletController, deployer);

    return {
      sharedWalletController,
      tokenMock
    };
  }

  async function deployAndConfigureContracts(): Promise<Fixture> {
    const fixture = await deployContracts();
    const { sharedWalletController, tokenMock } = fixture;

    await proveTx(sharedWalletController.grantRole(GRANTOR_ROLE, deployer.address));
    await proveTx(sharedWalletController.grantRole(ADMIN_ROLE, admin.address));

    // Mint initial balances for participants
    for (const participant of participants) {
      await proveTx(tokenMock.mint(participant.address, BALANCE_INITIAL));
      await proveTx(connect(tokenMock, participant).approve(getAddress(sharedWalletController), ALLOWANCE_MAX));
    }

    return fixture;
  }

  async function pauseContract(contract: Contract) {
    await proveTx(contract.grantRole(GRANTOR_ROLE, deployer.address));
    await proveTx(contract.grantRole(PAUSER_ROLE, deployer.address));
    await proveTx(contract.pause());
  }

  describe("Function 'initialize()'", async () => {
    it("Configures the contract as expected", async () => {
      const { sharedWalletController, tokenMock } = await setUpFixture(deployContracts);

      // The underlying token contract address
      // expect(await sharedWalletController.underlyingToken()).to.equal(getAddress(tokenMock));

      // Role hashes
      expect(await sharedWalletController.OWNER_ROLE()).to.equal(OWNER_ROLE);
      expect(await sharedWalletController.GRANTOR_ROLE()).to.equal(GRANTOR_ROLE);
      expect(await sharedWalletController.PAUSER_ROLE()).to.equal(PAUSER_ROLE);
      expect(await sharedWalletController.RESCUER_ROLE()).to.equal(RESCUER_ROLE);
      expect(await sharedWalletController.ADMIN_ROLE()).to.equal(ADMIN_ROLE);

      // The role admins
      expect(await sharedWalletController.getRoleAdmin(OWNER_ROLE)).to.equal(OWNER_ROLE);
      expect(await sharedWalletController.getRoleAdmin(GRANTOR_ROLE)).to.equal(OWNER_ROLE);
      expect(await sharedWalletController.getRoleAdmin(PAUSER_ROLE)).to.equal(GRANTOR_ROLE);
      expect(await sharedWalletController.getRoleAdmin(RESCUER_ROLE)).to.equal(GRANTOR_ROLE);
      expect(await sharedWalletController.getRoleAdmin(ADMIN_ROLE)).to.equal(GRANTOR_ROLE);

      // The deployer should have the owner role, but not the other roles
      expect(await sharedWalletController.hasRole(OWNER_ROLE, deployer.address)).to.equal(true);
      expect(await sharedWalletController.hasRole(GRANTOR_ROLE, deployer.address)).to.equal(false);
      expect(await sharedWalletController.hasRole(PAUSER_ROLE, deployer.address)).to.equal(false);
      expect(await sharedWalletController.hasRole(RESCUER_ROLE, deployer.address)).to.equal(false);
      expect(await sharedWalletController.hasRole(ADMIN_ROLE, deployer.address)).to.equal(false);

      // The initial contract state is unpaused
      expect(await sharedWalletController.paused()).to.equal(false);

      // Default values of the internal structures, mappings and variables. Also checks the set of fields
      const wpPair: WalletParticipantPair = {
        wallet: sharedWallets[0].address,
        participant: participants[0].address
      };
      checkEquality(
        (await sharedWalletController.getParticipantStates([wpPair]))[0],
        { ...defaultParticipantStateView, wallet: wpPair.wallet, participant: wpPair.participant }
      );
      expect(await sharedWalletController.getParticipantBalance(wpPair.wallet, wpPair.participant)).to.equal(0);
      expect(await sharedWalletController.getParticipantWallets(wpPair.participant)).to.deep.equal([]);
      expect(await sharedWalletController.getParticipants(wpPair.wallet)).to.deep.equal([]);
      expect(await sharedWalletController.isParticipant(wpPair.wallet, wpPair.participant)).to.equal(false);
      expect(await sharedWalletController.isParticipant(wpPair.wallet, wpPair.participant)).to.equal(false);
      expect(await sharedWalletController.getWalletCount()).to.equal(0);
      expect(await sharedWalletController.getAggregatedBalance()).to.equal(0);
    });

    it("Is reverted if it is called a second time", async () => {
      const { sharedWalletController, tokenMock } = await setUpFixture(deployContracts);
      await expect(sharedWalletController.initialize(getAddress(tokenMock)))
        .to.be.revertedWithCustomError(sharedWalletController, ERROR_NAME_INVALID_INITIALIZATION);
    });

    it("Is reverted if the passed token address is zero", async () => {
      const anotherContract = await upgrades.deployProxy(
        sharedWalletControllerFactory,
        [],
        { initializer: false }
      ) as Contract;

      await expect(anotherContract.initialize(ADDRESS_ZERO))
        .to.be.revertedWithCustomError(anotherContract, ERROR_NAME_WALLET_ADDRESS_ZERO);
    });

    it("Is reverted for the contract implementation if it is called even for the first time", async () => {
      const tokenAddress = participants[0].address;
      const implementation = await sharedWalletControllerFactory.deploy() as Contract;
      await implementation.waitForDeployment();

      await expect(implementation.initialize(tokenAddress))
        .to.be.revertedWithCustomError(implementation, ERROR_NAME_INVALID_INITIALIZATION);
    });
  });

  describe("Function 'upgradeToAndCall()'", async () => {
    it("Executes as expected", async () => {
      const { sharedWalletController } = await setUpFixture(deployContracts);
      await checkContractUupsUpgrading(sharedWalletController, sharedWalletControllerFactory);
    });

    it("Is reverted if the caller does not have the owner role", async () => {
      const { sharedWalletController } = await setUpFixture(deployContracts);

      await expect(connect(sharedWalletController, stranger).upgradeToAndCall(getAddress(sharedWalletController), "0x"))
        .to.be.revertedWithCustomError(sharedWalletController, ERROR_NAME_ACCESS_CONTROL_UNAUTHORIZED_ACCOUNT)
        .withArgs(stranger.address, OWNER_ROLE);
    });

    it("Is reverted if the provided implementation address does not belong to a controller contract", async () => {
      const { sharedWalletController, tokenMock } = await setUpFixture(deployContracts);

      await expect(sharedWalletController.upgradeToAndCall(getAddress(tokenMock), "0x"))
        .to.be.revertedWithCustomError(sharedWalletController, ERROR_NAME_IMPLEMENTATION_ADDRESS_INVALID);
    });
  });

  describe("Function 'createWallet()'", async () => {
    it("Executes as expected and emits the correct events", async () => {
      const { sharedWalletController } = await setUpFixture(deployAndConfigureContracts);
      const wpPairs: WalletParticipantPair[] = [
        { wallet: sharedWallets[0].address, participant: participants[0].address },
        { wallet: sharedWallets[0].address, participant: participants[1].address }
      ];
      const walletAddress = sharedWallets[0].address;
      const participantAddresses: string[] = wpPairs.map(p => p.participant);

      const tx = await connect(sharedWalletController, admin).createWallet(walletAddress, participantAddresses);
      await proveTx(tx);

      const actualParticipantStates = await sharedWalletController.getParticipantStates(wpPairs);
      const expectedParticipantStates: ParticipantStateView[] = wpPairs.map((p, i) => ({
        ...defaultParticipantStateView,
        wallet: p.wallet,
        participant: p.participant,
        status: ParticipantStatus.Registered,
        index: BigInt(i),
        balance: 0n
      }));
      expect(actualParticipantStates.length).to.equal(expectedParticipantStates.length);
      for (let i = 0; i < expectedParticipantStates.length; ++i) {
        checkEquality(actualParticipantStates[i], expectedParticipantStates[i], i);
      }
      expect(await sharedWalletController.getWalletCount()).to.equal(1);

      await expect(tx)
        .to.emit(sharedWalletController, EVENT_NAME_WALLET_CREATED)
        .withArgs(walletAddress);
      for (const participantAddress of participantAddresses) {
        await expect(tx)
          .to.emit(sharedWalletController, EVENT_NAME_PARTICIPANT_ADDED)
          .withArgs(walletAddress, participantAddress);
      }
    });

    it("Is reverted if the caller does not have the admin role", async () => {
      const { sharedWalletController } = await setUpFixture(deployAndConfigureContracts);

      await expect(
        connect(sharedWalletController, stranger).createWallet(sharedWallets[0].address, [participants[0].address])
      ).to.be.revertedWithCustomError(
        sharedWalletController,
        ERROR_NAME_ACCESS_CONTROL_UNAUTHORIZED_ACCOUNT
      ).withArgs(stranger.address, ADMIN_ROLE);
    });

    it("Is reverted if the provided wallet address is zero", async () => {
      const { sharedWalletController } = await setUpFixture(deployAndConfigureContracts);
      const wrongWallet = (ADDRESS_ZERO);

      await expect(connect(sharedWalletController, admin).createWallet(wrongWallet, [participants[0].address]))
        .to.be.revertedWithCustomError(sharedWalletController, ERROR_NAME_WALLET_ADDRESS_ZERO);
    });

    it("Is reverted if the participants array is empty", async () => {
      const { sharedWalletController } = await setUpFixture(deployAndConfigureContracts);

      await expect(connect(sharedWalletController, admin).createWallet(sharedWallets[0].address, []))
        .to.be.revertedWithCustomError(sharedWalletController, ERROR_NAME_PARTICIPANT_ARRAY_EMPTY);
    });
  });
});
