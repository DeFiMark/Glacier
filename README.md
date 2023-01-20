# Glacier

This repo is a collection of hardhat projects

`cd` into each one, run `npm i` to install dependencies

run `npx hardhat run scripts/deploy.js --network <NETWORK NAME>` to deploy that particular contract for the directory you are in.

Steps to deploy all:

1. Authorizer (note the address, you'll need it to deploy the vault)
1. Vault (note the address, you'll nede it to deploy teh weighted pool factory)
1. Weighted Pool Factory (0xf5F696Db8e655aa47f1aFD6EA9e5DF3510E09cCc)
1. Weighted Pool 2 Tokens Factory (0xFBfa0777f84772891eFB9Cb79abDB139A258FD17)
1. Stable Pool Factory (0x5942b6a8BdB34F7C463E60745A6c4aFC3E62910c)
1. Stable Phantom Pool Factory (0x91a541A956747480444822D07Cd305E2aDb94b6e)
1. Yearn Linear Pool Factory (0x56B323FcC7a91ffE71A6dDCA2DA85AaD59C96587)
1. LiquidityBootstrappingPoolFactory
