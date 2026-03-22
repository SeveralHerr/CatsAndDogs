/**
 * 🦞 Raining Cats & Dogs — Studio Server
 * Bridges the dashboard UI to Claude AI + Godot CLI
 * POST /prompt → Claude edits GDScript → Godot re-exports → response
 */

const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const { execSync, spawn } = require('child_process');
const Anthropic = require('@anthropic-ai/sdk');

const app = express();
app.use(cors());
app.use(express.json());

const PROJECT_DIR = __dirname;
const GAME_SCRIPT = path.join(PROJECT_DIR, 'scripts/Game.gd');
const EXPORT_DIR = path.join(PROJECT_DIR, 'export/web');
const GODOT = '/Applications/Godot.app/Contents/MacOS/Godot';
const SCREENSHOTS_DIR = path.join(PROJECT_DIR, 'playtester/screenshots');

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// Serve dashboard + game export
app.use('/game', express.static(EXPORT_DIR));
app.use('/screenshots', express.static(SCREENSHOTS_DIR));
app.use(express.static(path.join(PROJECT_DIR, 'studio-dashboard')));

// SSE endpoint for streaming responses
const sseClients = new Set();
app.get('/events', (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders();
  sseClients.add(res);
  req.on('close', () => sseClients.delete(res));
});

function broadcast(type, data) {
  const msg = `data: ${JSON.stringify({ type, ...data })}\n\n`;
  sseClients.forEach(c => c.write(msg));
}

// Get current script contents
app.get('/script', (req, res) => {
  res.json({ content: fs.readFileSync(GAME_SCRIPT, 'utf8') });
});

// List screenshots
app.get('/screenshots-list', (req, res) => {
  try {
    const files = fs.readdirSync(SCREENSHOTS_DIR)
      .filter(f => f.endsWith('.png'))
      .sort()
      .slice(-12); // last 12
    res.json({ files });
  } catch { res.json({ files: [] }); }
});

// Main prompt endpoint
app.post('/prompt', async (req, res) => {
  const { message } = req.body;
  if (!message) return res.status(400).json({ error: 'No message' });

  res.json({ ok: true });
  broadcast('log', { level: 'info', text: `👤 Paul: ${message}` });
  broadcast('status', { step: 'ai', state: 'active', text: 'Claude thinking...' });

  try {
    const currentScript = fs.readFileSync(GAME_SCRIPT, 'utf8');

    broadcast('log', { level: 'info', text: '🤖 Claude analyzing + editing...' });

    // Stream response from Claude
    let fullResponse = '';
    let inCodeBlock = false;
    let newScript = '';
    let buffer = '';

    const stream = client.messages.stream({
      model: 'claude-opus-4-5',
      max_tokens: 8096,
      messages: [{
        role: 'user',
        content: `You are Clawdia 🦞, AI game developer for "It's Raining Cats & Dogs" built in Godot 4.

The current Game.gd script is:
\`\`\`gdscript
${currentScript}
\`\`\`

The user/game director says: "${message}"

Respond conversationally (1-3 sentences explaining what you're doing), then if code changes are needed, provide the COMPLETE updated Game.gd wrapped in:
\`\`\`gdscript
[full updated script here]
\`\`\`

RULES:
- Only output one code block if changes needed
- The code block must contain the FULL script (not a diff)
- Keep all existing functionality unless asked to change it
- GDScript 4.x syntax only
- No emoji in Label text nodes (web export issue)
- Use draw_* canvas functions for game objects`
      }]
    });

    for await (const chunk of stream) {
      if (chunk.type === 'content_block_delta' && chunk.delta.type === 'text_delta') {
        const text = chunk.delta.text;
        fullResponse += text;
        buffer += text;

        // Stream text chunks to UI
        broadcast('stream', { text });

        // Detect code block
        if (!inCodeBlock && buffer.includes('```gdscript')) {
          inCodeBlock = true;
          newScript = '';
          buffer = '';
        } else if (inCodeBlock) {
          if (buffer.includes('```')) {
            // End of code block
            newScript = buffer.split('```')[0];
            inCodeBlock = false;
            broadcast('log', { level: 'success', text: '✓ New script extracted' });
          } else {
            newScript += text;
          }
        }
      }
    }

    broadcast('stream_end', {});

    // If we got a new script, save + export
    if (newScript && newScript.trim().length > 100) {
      broadcast('log', { level: 'info', text: '💾 Saving updated Game.gd...' });
      fs.writeFileSync(GAME_SCRIPT, newScript.trim());

      broadcast('status', { step: 'export', state: 'active', text: 'Re-exporting...' });
      broadcast('log', { level: 'info', text: '📦 Godot re-exporting to web...' });

      try {
        execSync(
          `"${GODOT}" --headless --export-release "Web" "${EXPORT_DIR}/index.html" --path "${PROJECT_DIR}"`,
          { timeout: 60000, stdio: 'pipe' }
        );
        broadcast('log', { level: 'success', text: '✓ Export complete — game updated!' });
        broadcast('status', { step: 'export', state: 'done', text: '✓ Exported' });
        broadcast('game_updated', { timestamp: Date.now() });

        // Auto-commit
        execSync(`cd "${PROJECT_DIR}" && git add scripts/Game.gd && git commit -m "studio: ${message.slice(0, 60)}"`, { stdio: 'pipe' });
        broadcast('log', { level: 'success', text: '✓ Committed to git' });

      } catch (exportErr) {
        broadcast('log', { level: 'error', text: '✗ Export failed: ' + exportErr.message.slice(0, 100) });
        broadcast('status', { step: 'export', state: 'error', text: 'Export failed' });
      }
    } else {
      broadcast('log', { level: 'info', text: '💬 No code changes — just conversation' });
    }

    broadcast('status', { step: 'ai', state: 'done', text: '✓ Done' });

  } catch (err) {
    broadcast('log', { level: 'error', text: '✗ Error: ' + err.message });
    broadcast('status', { step: 'ai', state: 'error', text: 'Error' });
  }
});

// Trigger playtester
app.post('/playtest', (req, res) => {
  res.json({ ok: true });
  broadcast('log', { level: 'info', text: '🤖 Launching playtester...' });
  const py = spawn('/Users/pk/Projects/playwright-venv/bin/python',
    [path.join(PROJECT_DIR, 'playtester/playtester.py')],
    { cwd: PROJECT_DIR }
  );
  py.stdout.on('data', d => broadcast('log', { level: 'info', text: d.toString().trim() }));
  py.stderr.on('data', d => broadcast('log', { level: 'warn', text: d.toString().trim() }));
  py.on('close', () => broadcast('log', { level: 'success', text: '✓ Playtester done' }));
});

// Open Godot IDE
app.post('/open-godot', (req, res) => {
  try {
    execSync(`open -a Godot "${PROJECT_DIR}"`);
    broadcast('log', { level: 'success', text: '✓ Godot IDE opened' });
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

const PORT = 3742;
app.listen(PORT, () => {
  console.log(`🦞 Studio server running at http://localhost:${PORT}`);
  console.log(`   Dashboard: http://localhost:${PORT}`);
  console.log(`   Game preview: http://localhost:${PORT}/game`);
});
