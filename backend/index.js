/**
 * Zcash Relay Backend
 * Simple Express + WebSocket server
 * - Serves verification data from JSON
 * - Runs relay script for new blocks
 * - Broadcasts real-time updates via WebSocket
 */

const express = require('express');
const { spawn } = require('child_process');
const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');
const cors = require('cors');
const chokidar = require('chokidar');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = 3001;
const WS_PORT = 3002;

// Paths
const VERIFICATIONS_FILE = path.join(__dirname, '../frontend/src/data/verifications.json');
const RELAY_SCRIPT = path.join(__dirname, '../scripts/relay-block.sh');

// WebSocket server
const wss = new WebSocket.Server({ port: WS_PORT });

console.log(`WebSocket server on ws://localhost:${WS_PORT}`);

// Broadcast to all connected clients
function broadcast(data) {
  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(data));
    }
  });
}

// Watch verifications.json for changes
chokidar.watch(VERIFICATIONS_FILE).on('change', () => {
  console.log('[WATCH] verifications.json changed');
  try {
    const data = JSON.parse(fs.readFileSync(VERIFICATIONS_FILE, 'utf8'));
    broadcast({ type: 'update', data });
  } catch (err) {
    console.error('Failed to read verifications:', err);
  }
});

// API: Get all verifications
app.get('/api/verifications', (req, res) => {
  try {
    const data = JSON.parse(fs.readFileSync(VERIFICATIONS_FILE, 'utf8'));
    res.json(data);
  } catch (err) {
    res.status(500).json({ error: 'Failed to read verifications' });
  }
});

// API: Get single block verification
app.get('/api/verifications/:height', (req, res) => {
  try {
    const data = JSON.parse(fs.readFileSync(VERIFICATIONS_FILE, 'utf8'));
    const blockKey = `block_${req.params.height}`;
    if (data[blockKey]) {
      res.json(data[blockKey]);
    } else {
      res.status(404).json({ error: 'Block not found' });
    }
  } catch (err) {
    res.status(500).json({ error: 'Failed to read verifications' });
  }
});

// Track active verifications
const activeVerifications = new Map();

// API: Start block verification
app.post('/api/verify/:height', (req, res) => {
  const height = parseInt(req.params.height);
  
  if (activeVerifications.has(height)) {
    return res.status(400).json({ error: 'Verification already in progress' });
  }
  
  console.log(`[VERIFY] Starting verification for block ${height}`);
  
  const projectRoot = path.join(__dirname, '..');
  
  // Run relay script with venv activated
  const childProcess = spawn('bash', ['-c', `source ${projectRoot}/venv/bin/activate && ${RELAY_SCRIPT} ${height}`], {
    cwd: projectRoot,
    env: { 
      ...process.env,
      PATH: `${projectRoot}/venv/bin:${process.env.PATH}`,
      VIRTUAL_ENV: `${projectRoot}/venv`
    }
  });
  
  activeVerifications.set(height, childProcess);
  
  // Stream stdout
  childProcess.stdout.on('data', (data) => {
    const output = data.toString();
    console.log(`[RELAY ${height}]`, output.trim());
    
    // Parse TX completion
    const txMatch = output.match(/\[TX (\d+)\/19\]/);
    if (txMatch) {
      const step = parseInt(txMatch[1]);
      broadcast({ 
        type: 'progress', 
        height, 
        step,
        output: output.trim()
      });
    }
  });
  
  childProcess.stderr.on('data', (data) => {
    console.error(`[RELAY ${height} ERROR]`, data.toString());
  });
  
  childProcess.on('close', (code) => {
    activeVerifications.delete(height);
    console.log(`[VERIFY] Block ${height} completed with code ${code}`);
    broadcast({ 
      type: 'complete', 
      height, 
      success: code === 0 
    });
  });
  
  res.json({ status: 'started', height });
});

// API: Get verification status
app.get('/api/verify/:height/status', (req, res) => {
  const height = parseInt(req.params.height);
  const isActive = activeVerifications.has(height);
  res.json({ height, inProgress: isActive });
});

// API: Cancel verification
app.delete('/api/verify/:height', (req, res) => {
  const height = parseInt(req.params.height);
  const process = activeVerifications.get(height);
  
  if (process) {
    process.kill();
    activeVerifications.delete(height);
    res.json({ status: 'cancelled', height });
  } else {
    res.status(404).json({ error: 'No active verification' });
  }
});

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', activeVerifications: activeVerifications.size });
});

app.listen(PORT, () => {
  console.log(`Backend API on http://localhost:${PORT}`);
  console.log(`Watching: ${VERIFICATIONS_FILE}`);
});
