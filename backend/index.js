const express = require('express');
const { spawn } = require('child_process');
const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');
const cors = require('cors');
const chokidar = require('chokidar');
const { RpcProvider } = require('starknet');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = 3001;
const WS_PORT = 3002;

const provider = new RpcProvider({ 
  nodeUrl: 'https://starknet-sepolia.public.blastapi.io/rpc/v0_7'
});

const VERIFICATIONS_FILE = path.join(__dirname, '../frontend/src/data/verifications.json');
const RELAY_SCRIPT = path.join(__dirname, '../scripts/relay-block.sh');

const wss = new WebSocket.Server({ port: WS_PORT });
console.log('WebSocket server on ws://localhost:' + WS_PORT);

function broadcast(data) {
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(data));
    }
  });
}

// Queue system for concurrent requests
const verificationQueue = [];
let isProcessing = false;
let currentHeight = null;
let activeProcess = null;

async function processQueue() {
  if (isProcessing || verificationQueue.length === 0) return;
  
  isProcessing = true;
  const targetHeight = verificationQueue.shift();
  currentHeight = targetHeight;
  
  console.log('[QUEUE] Processing block ' + targetHeight);
  broadcast({ type: 'queue_update', current: targetHeight, queue: verificationQueue });
  
  try {
    await runVerification(targetHeight);
  } catch (err) {
    console.error('[QUEUE] Error:', err);
  }
  
  isProcessing = false;
  currentHeight = null;
  
  if (verificationQueue.length > 0) {
    processQueue();
  }
}

function addToQueue(height) {
  if (verificationQueue.includes(height)) {
    return { status: 'already_queued', position: verificationQueue.indexOf(height) + 1 };
  }
  if (currentHeight === height) {
    return { status: 'in_progress', height: height };
  }
  if (currentHeight !== null && height <= currentHeight) {
    return { status: 'will_be_covered', coveredBy: currentHeight };
  }
  for (const queued of verificationQueue) {
    if (height <= queued) {
      return { status: 'will_be_covered', coveredBy: queued };
    }
  }
  
  verificationQueue.push(height);
  console.log('[QUEUE] Added block ' + height);
  processQueue();
  return { status: 'queued', position: verificationQueue.length };
}

// Fetch REAL fee from Starknet transaction receipt
async function fetchTransactionFee(txHash) {
  try {
    await new Promise(r => setTimeout(r, 3000));
    const receipt = await provider.getTransactionReceipt(txHash);
    
    let actualFeeRaw = BigInt(0);
    let unit = 'FRI';
    
    if (receipt.actual_fee) {
      if (typeof receipt.actual_fee === 'object') {
        actualFeeRaw = BigInt(receipt.actual_fee.amount);
        unit = receipt.actual_fee.unit || 'FRI';
      } else {
        actualFeeRaw = BigInt(receipt.actual_fee);
      }
    }
    
    const actualFeeStrk = Number(actualFeeRaw) / 1e18;
    
    return {
      actualFee: actualFeeStrk,
      actualFeeRaw: actualFeeRaw.toString(),
      unit: unit
    };
  } catch (err) {
    console.error('[FEE] Error:', err.message);
    return { actualFee: 0, actualFeeRaw: '0', unit: 'FRI', error: err.message };
  }
}

async function updateTxWithRealFee(blockHeight, txHash, stepIndex) {
  try {
    const feeData = await fetchTransactionFee(txHash);
    const rawData = fs.readFileSync(VERIFICATIONS_FILE, 'utf8');
    const data = JSON.parse(rawData);
    const blockKey = 'block_' + blockHeight;
    
    if (data[blockKey] && data[blockKey].transactions) {
      const tx = data[blockKey].transactions.find(t => t.step === stepIndex);
      if (tx) {
        tx.actualFee = feeData.actualFee;
        tx.actualFeeRaw = feeData.actualFeeRaw;
        tx.unit = feeData.unit;
      }
      
      let totalFee = 0;
      for (const t of data[blockKey].transactions) {
        if (t.actualFee) totalFee += t.actualFee;
      }
      data[blockKey].totalFee = totalFee;
      
      fs.writeFileSync(VERIFICATIONS_FILE, JSON.stringify(data, null, 2));
      console.log('[FEE] Block ' + blockHeight + ' step ' + stepIndex + ': ' + feeData.actualFee.toFixed(8) + ' STRK');
    }
    return feeData;
  } catch (err) {
    console.error('[FEE] Update error:', err.message);
    return null;
  }
}

function runVerification(targetHeight) {
  return new Promise((resolve, reject) => {
    const projectRoot = path.join(__dirname, '..');
    console.log('[VERIFY] Starting block ' + targetHeight);
    
    const cmd = 'source ' + projectRoot + '/venv/bin/activate && ' + RELAY_SCRIPT + ' ' + targetHeight;
    const childProcess = spawn('bash', ['-c', cmd], {
      cwd: projectRoot,
      env: { 
        ...process.env,
        PATH: projectRoot + '/venv/bin:' + process.env.PATH,
        VIRTUAL_ENV: projectRoot + '/venv'
      }
    });
    
    activeProcess = childProcess;
    
    childProcess.stdout.on('data', async (data) => {
      const output = data.toString();
      console.log('[RELAY]', output.trim());
      
      const txMatch = output.match(/\[TX (\d+)\/19\]/);
      const hashMatch = output.match(/(0x[a-f0-9]{64})/i);
      
      if (txMatch) {
        const step = parseInt(txMatch[1]);
        const cleanOutput = output.replace(/\x1b\[[0-9;]*m/g, '').trim();
        broadcast({ type: 'progress', height: targetHeight, step: step, output: cleanOutput });
        
        if (hashMatch) {
          const txHash = hashMatch[1];
          updateTxWithRealFee(targetHeight, txHash, step).then(feeData => {
            if (feeData) {
              broadcast({ type: 'fee_update', height: targetHeight, step: step, fee: feeData });
            }
          });
        }
      }
    });
    
    childProcess.stderr.on('data', (data) => {
      console.error('[RELAY ERROR]', data.toString());
    });
    
    childProcess.on('close', (code) => {
      activeProcess = null;
      console.log('[VERIFY] Block ' + targetHeight + ' done, code ' + code);
      broadcast({ type: 'complete', height: targetHeight, success: code === 0 });
      code === 0 ? resolve() : reject(new Error('Failed'));
    });
  });
}

chokidar.watch(VERIFICATIONS_FILE).on('change', () => {
  try {
    const data = JSON.parse(fs.readFileSync(VERIFICATIONS_FILE, 'utf8'));
    broadcast({ type: 'update', data: data });
  } catch (err) {}
});

app.get('/api/verifications', (req, res) => {
  try {
    const data = JSON.parse(fs.readFileSync(VERIFICATIONS_FILE, 'utf8'));
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

app.get('/api/verifications/:height', (req, res) => {
  try {
    const data = JSON.parse(fs.readFileSync(VERIFICATIONS_FILE, 'utf8'));
    const blockKey = 'block_' + req.params.height;
    data[blockKey] ? res.json(data[blockKey]) : res.status(404).json({ error: 'Not found' });
  } catch (err) {
    res.status(500).json({ error: 'Failed' });
  }
});

app.post('/api/verify/:height', (req, res) => {
  const height = parseInt(req.params.height);
  if (isNaN(height) || height < 0) return res.status(400).json({ error: 'Invalid' });
  res.json(addToQueue(height));
});

app.get('/api/queue', (req, res) => {
  res.json({ isProcessing, current: currentHeight, queue: verificationQueue });
});

app.delete('/api/verify/current', (req, res) => {
  if (activeProcess) {
    activeProcess.kill();
    activeProcess = null;
    isProcessing = false;
    const cancelled = currentHeight;
    currentHeight = null;
    processQueue();
    res.json({ status: 'cancelled', height: cancelled });
  } else {
    res.status(404).json({ error: 'None active' });
  }
});

app.get('/api/fee/:txHash', async (req, res) => {
  res.json(await fetchTransactionFee(req.params.txHash));
});

app.post('/api/backfill-fees/:height', async (req, res) => {
  const height = parseInt(req.params.height);
  try {
    const data = JSON.parse(fs.readFileSync(VERIFICATIONS_FILE, 'utf8'));
    const blockKey = 'block_' + height;
    if (!data[blockKey]) return res.status(404).json({ error: 'Not found' });
    
    for (const tx of data[blockKey].transactions) {
      if (tx.txHash && tx.txHash.length === 66) {
        const feeData = await fetchTransactionFee(tx.txHash);
        tx.actualFee = feeData.actualFee;
        tx.actualFeeRaw = feeData.actualFeeRaw;
        await new Promise(r => setTimeout(r, 500));
      }
    }
    
    let totalFee = 0;
    for (const t of data[blockKey].transactions) {
      if (t.actualFee) totalFee += t.actualFee;
    }
    data[blockKey].totalFee = totalFee;
    fs.writeFileSync(VERIFICATIONS_FILE, JSON.stringify(data, null, 2));
    res.json({ status: 'ok', totalFee });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', isProcessing, currentHeight, queueLength: verificationQueue.length });
});

app.listen(PORT, () => {
  console.log('Backend on http://localhost:' + PORT);
  console.log('Queue system active - handles concurrent requests');
});
