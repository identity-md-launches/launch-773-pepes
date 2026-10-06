# Pepes (PEPES)

Pepes is a fixed-supply ERC-20. Its constructor mints **1,000,000,000 tokens
with 18 decimals** to the immediate deployer (`msg.sender`). The exact total
supply is **1000000000000000000000000000** base units (`10^27`).

## Contract and behavior

The deployment artifact is `src/Pepes.sol:Pepes`. It inherits the vendored
OpenZeppelin Contracts v5.1.0 ERC-20 implementation.

- Constructor arguments: none (`constructorArgs: []`); constructor value: zero.
- Name: `Pepes`; symbol: `PEPES`; decimals: `18`.
- Supply is created once. There is no external mint, burn, ownership, pause,
  blacklist, seizure, upgrade, or initialization function.
- Transfers deliver the exact amount, with no tax, fee, rebase, or exemption list.
- `transfer`, `approve`, and `transferFrom` return `true` on success and revert
  with ERC-6093 errors on invalid input, insufficient balance, or allowance.
- Zero-value transfers and self-transfers are supported. Transfers to the zero
  address and approvals to the zero spender are rejected.
- An approval replaces the existing allowance; setting it to zero revokes it.
  Finite allowances decrease on `transferFrom`; `uint256.max` remains unchanged.
  Even the deployer needs a holder's approval to use `transferFrom`.
- Minting and transfers emit `Transfer`; explicit approvals emit `Approval`.
  OpenZeppelin v5 does not emit `Approval` when `transferFrom` spends an allowance.
- The token has no recipient callbacks or external calls, and no time, oracle,
  randomness, chain-address, or environment dependencies.

## Build and check

Use Foundry with Solidity **0.8.26**, pinned by version in `foundry.toml`.
The configuration targets **Cancun**, enables the optimizer with 200 runs,
and sets `bytecode_hash = "none"` for reproducible launch bytecode.
FFI and filesystem cheatcode permissions are disabled.

```sh
forge build
forge test
forge fmt --check
```

All Solidity dependencies and their licenses are ordinary files under `lib/`;
there are no submodules or dependency installation steps. With Foundry and the
pinned compiler already installed, the project builds and tests without network
access. See `DEPENDENCIES.md` for versions and archive checksums.

Tests are independent of RPC endpoints, private keys, and environment variables.
Each test creates fresh state. The suite includes:

- Exact metadata and supply, mint events, EOA deployment, and CREATE2 deployment
  through a factory (the factory receives the supply, not `tx.origin`).
- Exact distribution/claim transfers and transfers in both pool directions.
- Whole-supply, zero-value, self, and delegated transfers; finite, maximum,
  replaced, and revoked allowances; standard events.
- Failure cases for overspending, missing/exceeded/revoked allowances, invalid
  addresses, and native currency, including unchanged state after reverts.
- Rejected mint/admin/burn calls from the deployer and a stranger, holder freedom
  to transfer, and a runtime check for forbidden opcodes.
- 256 runs per fuzz test, plus stateful invariants with 128 runs of 64 actions
  each checking supply conservation and modeled allowances.

The local pool-direction test checks token movements only. The supplied protected
launch harness additionally exercises a real Uniswap v4 PoolManager and requires
the launch system's contracts, manifest, addresses, and environment configuration.
Those are external to this token project; the full admission harness remains the
launch verifier's responsibility. No AMM price or launch economics is inferred
from the local test's illustrative amounts.

## Deployment and operational responsibilities

Deploy the creation bytecode for `src/Pepes.sol:Pepes` with no appended arguments,
no linked-library addresses, no native currency, and no post-deployment calls.
There is no deployment wrapper: a wrapper would itself become the immediate
deployer and receive the entire supply.

For a direct deployment, the deploying account receives all tokens. For the
IdentityMD custom-token flow, `ProjectFactory.launchCustom` creates the token;
the factory receives all tokens and performs the launch distribution separately.
The token never pre-distributes supply or treats the transaction origin as the
recipient. It needs no factory, distributor, pool-manager, or launch-number
constructor parameters, because every valid transfer already arrives whole.
There are no application contracts in this deliverable.

No target chain, factory address, paired currency, pool fee, tick spacing, opening
valuation, pool allocation, or remainder recipient was specified. The launch
operator must supply and review those parameters through the launch system and
use a chain compatible with the configured EVM target. This repository does not
invent a launch manifest or deploy contracts.

Before release, the operator is responsible for independent adversarial review,
reviewing the exact creation bytecode and compiler settings, verifying the
deployed source/runtime on the chosen explorer, and confirming metadata, total
supply, initial recipient, and actual factory/pool integration. The launch
operator handles the network's distribution and liquidity policy. No keys,
funded wallets, or broadcasting are part of this project.

Holders control their own custody and spender approvals. When changing an
existing nonzero allowance, revoke it and wait for confirmation before granting
the replacement to reduce the standard ERC-20 allowance replacement race;
revocation cannot undo a spend already executed. Unlimited approvals persist
until revoked. There is no administrator to recover lost tokens, undo transfers,
freeze a compromised account, or patch the deployed contract. Tokens sent to the
token contract itself or another contract unable to move them may be stranded.
Ordinary native-currency deposits revert; forced deposits have no recovery path.

Passing this suite is not a security audit. The checks performed for this
assignment are Foundry build, unit/fuzz/invariant tests, and formatting;
Slither and Mythril are not part of the recorded validation.
