# Vendored dependencies

The following source files are vendored unchanged as ordinary files. Their
original SPDX notices and licenses are retained. No package manager, submodule,
network fetch, compiler binary, or code generation is needed during verification.

| Library | Version | Included files | License |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | v5.1.0 | ERC20.sol, IERC20.sol, IERC20Metadata.sol, Context.sol, draft-IERC6093.sol | MIT (`lib/openzeppelin-contracts/LICENSE`) |
| forge-std | v1.9.7 | Complete `src/` tree (test support only) | MIT / Apache-2.0 (`lib/forge-std/LICENSE-MIT`, `lib/forge-std/LICENSE-APACHE`) |

Upstream release archives and SHA-256 digests used to obtain these files:

- OpenZeppelin: <https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.1.0>
  `8a3b08cfc756437ba3343901565b18182adb42ec1e621960240a19da5d738686`
- forge-std: <https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7>
  `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`

Only the transitive OpenZeppelin source needed by Pepes is included; unused
OpenZeppelin extensions are not vendored. `remappings.txt` resolves both libraries
within this repository. Foundry and solc are external verification tools, not
runtime dependencies; solc is pinned to version 0.8.26 in `foundry.toml`.
