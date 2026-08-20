import { StockSDK } from 'stock-sdk'

async function run() {
  console.log('正在连接行情服务器查询 600519 (贵州茅台)...')
  try {
    const sdk = new StockSDK({ timeout: 10000 })
    const [quote] = await sdk.quotes.cn(['600519'])
    if (!quote) {
      console.log('未获取到行情数据')
      return
    }
    console.log('------------------------------')
    console.log('股票名称:', quote.name)
    console.log('股票代码:', quote.code)
    console.log('当前价格:', quote.price)
    console.log('涨跌幅度:', quote.changePercent + '%')
    console.log('今开盘价:', quote.open)
    console.log('昨日收盘:', quote.prevClose)
    console.log('最高价:', quote.high)
    console.log('最低价:', quote.low)
    console.log('------------------------------')
  } catch (err) {
    console.error('获取行情失败:', err)
  }
}

await run()
