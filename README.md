# Monolith Cumpounder

Yearn V3 tokenized strategy that autocompounds a staked [Monolith](https://app.monolith.market) gov token, e.g. SWAN, the DAO token of swanUSD.

- Deposits stake the gov token into its staked gov token (instant and 1:1 both ways).
- The staked gov token earns the coin as revenue. Each report claims it and kicks it into the strategy's own Yearn dutch auction, which pays the strategy in the gov token. The next report restakes the proceeds.
- Only the strategy can kick its auction. Keepers can also claim and kick between reports with `kickAuction`. Management sets the auction's prices and can enable other tokens to sell with `enableAuctionToken`.
- Rewards at or below `minAmountToSell` are held until the next kick. Management can delegate the strategy's votes with `delegate`.
- `StrategyFactory.newStrategy(asset, name, staking)` deploys one per gov token. Only the factory's management can call it. Auction prices are set afterwards.
- `MonolithSwanAprOracle` works like the Monolith UI. It takes the market's current yearly revenue (the local reserve share of interest plus the PSM's sUSDS yield) times the stakers' share, prices it in the gov token and divides by the staked supply. The price is a manual one if set, else the Uniswap V4 pool's spot price. Governance and the keepers it allows can set the manual price.

`script/Deploy.s.sol` deploys the factory, the SWAN strategy, the APR oracle and a Yearn V3 vault (`yvSWAN`) with the strategy as its only strategy. Only the vault can deposit into the strategy. Profit unlocking (3 days) and fees live at the vault, so the strategy has neither. Vault role management goes to the Yearn RoleManager, whose `addNewVault` sets the vault's accountant. The strategy's votes are delegated to Inverse's multisig (`0x9D5Df30F475CEA915b1ed4C0CCa59255C897b61B`).

| Contract | Address |
| --- | --- |
| SWAN (asset) | `0xD0a32F6d4850F9D6DF7d4F8f84af1Fcd3Cf993CC` |
| sSWAN (staking) | `0xcBC108384e874D9B0436adE3918685BaA709e48c` |
| swanUSD (reward) | `0x9BF2B2F57A2968A0E81546Ed50cBbbb7C9d6e05E` |
| swanUSD/SWAN V4 pool (oracle price) | fee `6000`, tick spacing `60`, no hooks |

For a more complete overview of how the Tokenized Strategies work please visit the [TokenizedStrategy Repo](https://github.com/yearn/tokenized-strategy).

## How to start

### Requirements

- First you will need to install [Foundry](https://book.getfoundry.sh/getting-started/installation).
NOTE: If you are on a windows machine it is recommended to use [WSL](https://learn.microsoft.com/en-us/windows/wsl/install)

### Clone this repository

```sh
git clone --recursive https://github.com/yearn/tokenized-strategy-foundry-mix

cd tokenized-strategy-foundry-mix
```

### Set your environment Variables

Use the `.env.example` template to create a `.env` file and store the environement variables. You will need to populate the `RPC_URL` for the desired network(s). RPC url can be obtained from various providers, including [Ankr](https://www.ankr.com/rpc/) (no sign-up required) and [Infura](https://infura.io/).

Use .env file

1. Make a copy of `.env.example`
2. Add the value for `ETH_RPC_URL` and other example vars
     NOTE: If you set up a global environment variable, that will take precedence.

### Build the project

```sh
make build
```

Run tests

```sh
make test
```

## Strategy Writing

For a complete guide to creating a Tokenized Strategy please visit: https://docs.yearn.fi/developers/v3/strategy_writing_guide

NOTE: Compiler defaults to 8.23 but it can be adjusted in the foundry toml.

## Testing

Due to the nature of the BaseStrategy utilizing an external contract for the majority of its logic, the default interface for any tokenized strategy will not allow proper testing of all functions. Testing of your Strategy should utilize the pre-built [IStrategyInterface](https://github.com/yearn/tokenized-strategy-foundry-mix/blob/master/src/interfaces/IStrategyInterface.sol) to cast any deployed strategy through for testing, as seen in the Setup example. You can add any external functions that you add for your specific strategy to this interface to be able to test all functions with one variable.

Example:

```solidity
Strategy _strategy = new Strategy(asset, name);
IStrategyInterface strategy =  IStrategyInterface(address(_strategy));
```

Due to the permissionless nature of the tokenized Strategies, all tests are written without integration with any meta vault funding it. While those tests can be added, all V3 vaults utilize the ERC-4626 standard for deposit/withdraw and accounting, so they can be plugged in easily to any number of different vaults with the same `asset.`

Tests run in fork environment, you need to complete the full installation and setup to be able to run these commands.

```sh
make test
```

Run tests with traces (very useful)

```sh
make trace
```

Run specific test contract (e.g. `test/StrategyOperation.t.sol`)

```sh
make test-contract contract=StrategyOperationsTest
```

Run specific test contract with traces (e.g. `test/StrategyOperation.t.sol`)

```sh
make trace-contract contract=StrategyOperationsTest
```

See here for some tips on testing [`Testing Tips`](https://book.getfoundry.sh/forge/tests.html)

When testing on chains other than mainnet you will need to make sure a valid `CHAIN_RPC_URL` for that chain is set in your .env. You will then need to simply adjust the variable that RPC_URL is set to in the Makefile to match your chain.

To update to a new API version of the TokenizeStrategy you will need to simply remove and reinstall the dependency.

### Test Coverage

Run the following command to generate a test coverage:

```sh
make coverage
```

To generate test coverage report in HTML, you need to have installed [`lcov`](https://github.com/linux-test-project/lcov) and run:

```sh
make coverage-html
```

The generated report will be in `coverage-report/index.html`.

### Deployment

#### Contract Verification

Once the Strategy is fully deployed and verified, you will need to verify the TokenizedStrategy functions. To do this, navigate to the /#code page on Etherscan.

1. Click on the `More Options` drop-down menu
2. Click "is this a proxy?"
3. Click the "Verify" button
4. Click "Save"

This should add all of the external `TokenizedStrategy` functions to the contract interface on Etherscan.

## CI

This repo uses [GitHub Actions](.github/workflows) for CI. There are three workflows: lint, test and slither for static analysis.

To enable test workflow you need to add the `ETH_RPC_URL` secret to your repo. For more info see [GitHub Actions docs](https://docs.github.com/en/codespaces/managing-codespaces-for-your-organization/managing-encrypted-secrets-for-your-repository-and-organization-for-github-codespaces#adding-secrets-for-a-repository).

If the slither finds some issues that you want to suppress, before the issue add comment: `//slither-disable-next-line DETECTOR_NAME`. For more info about detectors see [Slither docs](https://github.com/crytic/slither/wiki/Detector-Documentation).

### Coverage

If you want to use [`coverage.yml`](.github/workflows/coverage.yml) workflow on other chains than mainnet, you need to add the additional `CHAIN_RPC_URL` secret.

Coverage workflow will generate coverage summary and attach it to PR as a comment. To enable this feature you need to add the [`GH_TOKEN`](.github/workflows/coverage.yml#L53) secret to your Github repo. Token must have permission to "Read and Write access to pull requests". To generate token go to [Github settings page](https://github.com/settings/tokens?type=beta). For more info see [GitHub Access Tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).
