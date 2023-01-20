require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require('dotenv').config({path:'../.env'});
const privateKey = process.env.PRIVATE_KEY;
const etherscanKey = process.env.ETHERSCAN_KEY;
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  networks: {
    hardhat: {
      chainId: 1337
    },
    bscTestnet: {
      url: 'https://data-seed-prebsc-2-s3.binance.org:8545/',
      accounts: [privateKey]
    },
    bscMainnet: {
      url: 'https://bsc-dataseed.binance.org',
      accounts: [privateKey]
    },
  },
  etherscan: {
    apiKey: etherscanKey
  },
  solidity: {
    compilers: [
      {
        version: "0.8.7",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.8.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.7.1",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      {
        version: "0.7.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
      // {
      //   version: "0.8.0",
      //   settings: {
      //     optimizer: {
      //       enabled: true,
      //       runs: 200
      //     }
      //   }
      // }
    ]
  }
};
