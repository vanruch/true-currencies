import assertRevert from './helpers/assertRevert'
import expectThrow from './helpers/expectThrow'
import assertBalance from './helpers/assertBalance'

const TrueUSDMock = artifacts.require("TrueUSDMock")
const Registry = artifacts.require("Registry")
const GlobalPause = artifacts.require("GlobalPause")

contract('RedeemToken', function (accounts) {
    const [_, owner, oneHundred, anotherAccount] = accounts
    const notes = "some notes"
    const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000'

    describe('--Redeemable Token--', function () {
        beforeEach(async function () {
            this.token = await TrueUSDMock.new(oneHundred, 100*10**18, { from: owner })
            this.globalPause = await GlobalPause.new({ from: owner })
            this.registry = await Registry.new({ from: owner })
            await this.token.setGlobalPause(this.globalPause.address, { from: owner })    
            await this.token.setRegistry(this.registry.address, { from: owner })
            await this.registry.setAttribute(oneHundred, "canBurn", 1, notes, { from: owner })
            await this.token.setBurnBounds(10*10**18, 1000*10**18, { from: owner }) 
        })

        it('transfer to 0x0 burns trueUSD', async function(){
            await assertBalance(this.token, oneHundred, 100*10**18)
            await this.token.transfer(ZERO_ADDRESS, 10*10**18, {from : oneHundred})
            await assertBalance(this.token, oneHundred, 90*10**18)
            const totalSupply = await this.token.totalSupply()
            assert.equal(Number(totalSupply),90*10**18)
        })

        it('transfer to 0x0 generates burn event', async function(){
            const {logs} = await this.token.transfer(ZERO_ADDRESS, 10*10**18, {from : oneHundred})
            
            assert.equal(logs[0].event, 'Burn')
            assert.equal(logs[0].args.burner,oneHundred)
            assert.equal(Number(logs[0].args.value),10*10**18)

            assert.equal(logs[1].event, 'Transfer')
            assert.equal(logs[1].args.from,oneHundred)
            assert.equal(logs[1].args.to,ZERO_ADDRESS)
            assert.equal(Number(logs[1].args.value),10*10**18)
        })

        it('transfer to 0x0 will fail if user does not have canBurn attribute', async function(){
            await this.token.transfer(anotherAccount, 20*10**18, {from : oneHundred})
            await assertBalance(this.token, anotherAccount, 20*10**18)
            await assertRevert(this.token.transfer(ZERO_ADDRESS, 10*10**18, {from : anotherAccount}))
        })

        it('transferFrom to 0x0 fails', async function(){
            await this.token.approve(anotherAccount, 10*10**18, {from : oneHundred})
            await assertRevert(this.token.transferFrom(oneHundred,ZERO_ADDRESS, 10*10**18, {from : anotherAccount}))
        })
    })
})
