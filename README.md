# Claim Fee Maker

Maker protocol integration to offer fixed-rate vaults as a feature on existing collateral types like ETH-A, WBTC-A, et cetra.

## Requirements

- [Dapptools](https://github.com/dapphub/dapptools)

## Deployment

`ClaimFee` handles the complete lifecycle of CLAIM-FEE balances for all collateral types. We recommend setting up this Claim Fee instance with [dss-gate](https://github.com/maker-claim-fee/dss-gate) which allows governance to set draw limits on the amount of dai the instance can draw through `vat.suck()`. Alternatively, the claim fee instance can also be setup directly with a working Vat address of a Maker protocol deployment.

```bash
dapp build # build repo
dapp test # run tests
make deploy-cfm gate=0x1234...
```

After deployment, the claim fee instance address needs to be authorized by its linked Vat address or dss-gate for it to draw Dai and settle CLAIM-FEE balance holders.

## Disclaimer

This code belongs to the MakerDAO community and the Copyright for the code belongs to the Dai Foundation.
