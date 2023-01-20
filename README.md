# Glacier

This repo is a collection of hardhat projects

`cd` into each one, run `npm i` to install dependencies

run `npx hardhat run scripts/deploy.js --network <NETWORK NAME>` to deploy that particular contract for the directory you are in.

Steps to deploy all:

1. Authorizer (note the address, you'll need it to deploy the vault)
1. Vault (note the address, you'll nede it to deploy the rest of the contracts: 0xE9f6c7B3B4293C9a9Ff33e98350e595B87f4c5b3)
1. Weighted Pool Factory (0xf5F696Db8e655aa47f1aFD6EA9e5DF3510E09cCc)
1. Weighted Pool 2 Tokens Factory (0xFBfa0777f84772891eFB9Cb79abDB139A258FD17)
1. Stable Pool Factory (0x5942b6a8BdB34F7C463E60745A6c4aFC3E62910c)
1. Stable Phantom Pool Factory (0x91a541A956747480444822D07Cd305E2aDb94b6e)
1. Yearn Linear Pool Factory (0x56B323FcC7a91ffE71A6dDCA2DA85AaD59C96587)
1. LiquidityBootstrappingPoolFactory (note the address, you'll need it to deploy the CopperProxy: 0x426aa291eEFD1ad526a7614Edf158b6C3D35cCC0)
1. MetastablePoolFactory (0x80357ce781dd4D4EA6f07Ced8cA91432700Ef924)
1. Protocol Fees Collector (0x0C4422Ed05123cE458ab65db1a169b54bAec314a)
1. BeethovenxToken (note the address, you'll need it to deploy the master chef: 0x2b245805A3601458fba61921e166e7A58bb09619)
1. MasterChef (0x866B786C05Ac9A9Af0CAFA68D9B7aE55eB323311)
1. Timelock (0xBD823a1595C4d3A5f34F1a49dAb41039b574A13C)
1. BeetsBar (0x109bb4F7624E8db22416299fE863887B2c63c65b)
1. CopperProxy (0x0C7cFF1DBEc9db3130B046660C2ef9b4f9Ca7173)

Tip: If you need to change the vault, do a search for const vault = <previous address of the vault> and do a find and replace -- it exists in a lot of scripts.
