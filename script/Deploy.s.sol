// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {IVaultFactory} from "@yearn-vaults/interfaces/IVaultFactory.sol";

import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";
import {StrategyFactory} from "../src/StrategyFactory.sol";
import {MonolithSwanAprOracle} from "../src/periphery/MonolithSwanAprOracle.sol";

// ---- Usage ----

// deploy:
// forge script script/Deploy.s.sol:Deploy --verify -g 250 --slow --etherscan-api-key $KEY --rpc-url $RPC_URL --broadcast

contract Deploy is Script {

    bool public isTest;
    address public s_management;
    address public s_performanceFeeRecipient;
    address public s_keeper;
    address public s_emergencyAdmin;
    address public s_roleManager;
    StrategyFactory public s_factory;
    IStrategyInterface public s_newStrategy;
    IVault public s_vault;
    MonolithSwanAprOracle public s_oracle;

    address public constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7; // SMS mainnet
    address public constant ACCOUNTANT = 0x5A74Cb32D36f2f517DB6f7b0A0591e09b22cDE69; // SMS mainnet accountant
    address public constant DEPLOYER = 0x420ACF637D662b80cca8bEfb327AA24039E7e0Fa; // gm.johnnyonline.eth
    address public constant YHAAS = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E; // yHAAS
    address public constant ROLE_MANAGER = 0xb3bd6B2E61753C311EFbCF0111f75D29706D9a41; // Yearn RoleManager
    IVaultFactory public constant VAULT_FACTORY = IVaultFactory(0x770D0d1Fb036483Ed4AbB6d53c1C88fb277D812F); // 3.0.4 Vault Factory

    address public constant SWAN = 0xD0a32F6d4850F9D6DF7d4F8f84af1Fcd3Cf993CC;
    address public constant SSWAN = 0xcBC108384e874D9B0436adE3918685BaA709e48c;
    address public constant INVERSE = 0x9D5Df30F475CEA915b1ed4C0CCa59255C897b61B; // Inverse multisig

    function run() public {
        uint256 _pk = isTest ? 42069 : vm.envUint("DEPLOYER_PRIVATE_KEY");
        address _deployer = vm.addr(_pk);

        if (!isTest) {
            require(_deployer == DEPLOYER, "!deployer");

            s_management = SMS;
            s_performanceFeeRecipient = ACCOUNTANT;
            s_keeper = YHAAS;
            s_emergencyAdmin = SMS;
            s_roleManager = ROLE_MANAGER;
        }

        string memory _name = "Monolith SWAN Cumpounder";

        vm.startBroadcast(_pk);

        // deploy. The deployer manages the factory and hands each strategy over to `s_management`
        s_factory = new StrategyFactory(_deployer, s_performanceFeeRecipient, s_keeper, s_emergencyAdmin);
        s_newStrategy = IStrategyInterface(s_factory.newStrategy(SWAN, _name, SSWAN));
        s_vault = IVault(VAULT_FACTORY.deploy_new_vault(SWAN, "SWAN yVault", "yvSWAN", _deployer, 3 days));
        s_oracle = new MonolithSwanAprOracle(_deployer);

        // init strategy. Only the vault deposits, so it unlocks profit and charges fees instead
        s_newStrategy.acceptManagement();
        s_newStrategy.setMinAmountToSell(s_newStrategy.REWARDS_TOKEN(), 100e18); // 100 swanUSD
        s_newStrategy.setAuctionStartingPrice(100_000e18); // 100k SWAN per lot
        s_newStrategy.setMinimumAuctionPrice(1e18); // 1 SWAN per swanUSD
        s_newStrategy.setProfitMaxUnlockTime(0);
        s_newStrategy.setPerformanceFee(0);
        s_newStrategy.setAllowed(address(s_vault), true);
        s_newStrategy.delegate(INVERSE); // Inverse votes the strategy's sSWAN
        s_newStrategy.setPendingManagement(s_management);

        // init vault
        s_vault.set_role(_deployer, 16383); // ALL
        s_vault.set_role(s_keeper, 32); // REPORTING_MANAGER
        s_vault.set_deposit_limit(type(uint256).max);
        s_vault.set_auto_allocate(true);
        s_vault.add_strategy(address(s_newStrategy));
        s_vault.update_max_debt_for_strategy(address(s_newStrategy), type(uint256).max);
        s_vault.transfer_role_manager(s_roleManager);
        s_vault.set_role(_deployer, 0);

        // init oracle
        s_oracle.setPool(address(s_newStrategy), 6_000, 60, address(0)); // swanUSD/SWAN 0.6% V4 pool
        s_oracle.setKeeper(_deployer, true); // Can set manual prices without governance
        s_oracle.transferGovernance(s_management);

        vm.stopBroadcast();

        if (!isTest) {
            console.log("Factory address: %s", address(s_factory));
            console.log("Strategy address: %s", address(s_newStrategy));
            console.log("Vault address: %s", address(s_vault));
            console.log("APR oracle address: %s", address(s_oracle));
        }
    }

}
