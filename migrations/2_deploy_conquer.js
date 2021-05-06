const Token = artifacts.require("Token");

const blackHoleVaultAddress = '0x7d7ca00C504Ec3d64325d27c16B9EdC1D04413d3';
const spaceWasteVaultAddress = '0x8749e0E2E09C22cdD5A33F26a7B768a3b1ee922f';
const devAddress = '0xA2474F4DB32872d98e1D2f5517a0a1837531036E';
const routerAddress = '0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F';

module.exports = function (deployer) {
  deployer.deploy(Token, blackHoleVaultAddress, devAddress, routerAddress, spaceWasteVaultAddress);
};
