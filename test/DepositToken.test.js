// import assertRevert from './helpers/assertRevert'
// import expectThrow from './helpers/expectThrow'
// import assertBalance from './helpers/assertBalance'

// const TrueUSDMock = artifacts.require("TrueUSDMock")
// const Registry = artifacts.require("Registry")
// const GlobalPause = artifacts.require("GlobalPause")

// contract('DepositToken', function (accounts) {
//     const [_, owner, oneHundred, anotherAccount] = accounts
//     const notes = "some notes"
//     const DEPOSIT_ADDRESS = anotherAccount.slice(0,34) + '00000000'

//     describe('--Deposit Token--', function () {
//         beforeEach(async function () {
//             this.token = await TrueUSDMock.new(oneHundred, 100*10**18, { from: owner })
//             this.globalPause = await GlobalPause.new({ from: owner })
//             this.registry = await Registry.new({ from: owner })
//             this.token.initialize(100*10**18,{from: owner})
//             await this.token.setGlobalPause(this.globalPause.address, { from: owner })    
//             await this.token.setRegistry(this.registry.address, { from: owner })
//             await this.registry.setAttribute(DEPOSIT_ADDRESS, "isDepositAddress", Number(anotherAccount), web3.fromUtf8(notes), { from: owner })

//         })

//         it('transfer to anotherAccount', async function(){
//             console.log("hex form",Number(anotherAccount))
//             console.log(web3.utf8ToHex(Number(anotherAccount)))
//             console.log(anotherAccount)
//             let attr1 = await this.registry.hasAttribute(DEPOSIT_ADDRESS, "isDepositAddress",{from: owner})
//             let attr2 = await this.registry.getAttribute(anotherAccount, 'isDepositAddress',{from: owner})

//             console.log('attr', attr1)
//             console.log('attr', attr2)

//             console.log(Number(await this.token.balanceOf(oneHundred)))
//             await this.token.transfer(anotherAccount, 50, {oneHundred})
//             await assertBalance(this.token,anotherAccount, 50)
//         })


//         it('transfers a deposit address of another account forwards tokens to anotherAccount', async function(){
//             const depositAddressOne = anotherAccount.slice(0,34) + '00000000';
//             const depositAddressTwo = anotherAccount.slice(0,34) + '20000000';
//             const depositAddressThree = anotherAccount.slice(0,34) + '40000000';
//             const depositAddressFour = anotherAccount.slice(0,34) + '00500000';
//             await this.token.transfer(depositAddressOne, 10, {oneHundred})
//             await this.token.transfer(depositAddressTwo, 10, {oneHundred})
//             await this.token.transfer(depositAddressThree, 10, {oneHundred})
//             await this.token.transfer(depositAddressFour, 10, {oneHundred})
//             await assertBalance(this.token,anotherAccount, 40)
//         })

//         it('can remove deposit address', async function(){
//             await this.registry.setAttribute(DEPOSIT_ADDRESS, "isDepositAddress", 0, notes, { from: owner })
//             const depositAddressOne = anotherAccount.slice(0,41) + '0';
//             const depositAddressTwo = anotherAccount.slice(0,41) + '1';
//             const depositAddressThree = anotherAccount.slice(0,40) + '8';
//             const depositAddressFour = anotherAccount.slice(0,41) + '25';
//             await this.token.transfer(depositAddressOne, 10, {oneHundred})
//             await this.token.transfer(depositAddressTwo, 10, {oneHundred})
//             await this.token.transfer(depositAddressThree, 10, {oneHundred})
//             await this.token.transfer(depositAddressFour, 10, {oneHundred})
//             await assertBalance(this.token,anotherAccount, 0)
//         })
//     })
// })