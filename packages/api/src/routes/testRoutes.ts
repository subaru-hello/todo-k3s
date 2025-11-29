import { Hono } from 'hono';
import { exec } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, writeFile, unlink } from 'node:fs/promises';
import os from 'node:os';

const app = new Hono();
const execPromise = promisify(exec);

// 1. child_process.exec()テスト（gVisorで失敗する）
app.get('/exec', async (c) => {
  try {
    const { stdout } = await execPromise('whoami');
    return c.json({
      status: 'success',
      runtime: 'runc',
      output: stdout.trim(),
      message: 'Command executed successfully'
    });
  } catch (error: any) {
    return c.json({
      status: 'error',
      runtime: 'gvisor (suspected)',
      message: error.message,
      hint: 'gVisor restricts process execution via execve syscall'
    }, 500);
  }
});

// 2. /proc/cpuinfo読み取りテスト（gVisorで仮想化される）
app.get('/sysinfo', async (c) => {
  try {
    const cpuinfo = await readFile('/proc/cpuinfo', 'utf-8');
    const cpuCount = (cpuinfo.match(/processor\s+:/g) || []).length;
    const modelMatch = cpuinfo.match(/model name\s+:\s+(.+)/);

    return c.json({
      status: 'success',
      cpuCount,
      cpuModel: modelMatch ? modelMatch[1].trim() : 'unknown',
      preview: cpuinfo.substring(0, 300),
      note: 'This info may be virtualized in gVisor'
    });
  } catch (error: any) {
    return c.json({
      status: 'error',
      message: error.message
    }, 500);
  }
});

// 3. ファイルシステム操作テスト（パフォーマンス比較）
app.get('/filesystem', async (c) => {
  try {
    const tmpFile = '/tmp/gvisor-test.txt';
    const testData = `Test from ${os.hostname()} at ${new Date().toISOString()}`;

    const startTime = Date.now();
    await writeFile(tmpFile, testData);
    const readData = await readFile(tmpFile, 'utf-8');
    await unlink(tmpFile);
    const duration = Date.now() - startTime;

    return c.json({
      status: 'success',
      writtenData: testData,
      readData: readData,
      match: testData === readData,
      durationMs: duration,
      tmpDir: os.tmpdir()
    });
  } catch (error: any) {
    return c.json({
      status: 'error',
      message: error.message
    }, 500);
  }
});

// 4. ランタイム判定エンドポイント
app.get('/runtime-info', async (c) => {
  try {
    let runtime = 'unknown';
    let detectionMethod = 'none';

    // 環境変数から判定（Deploymentで設定）
    if (process.env.RUNTIME_TYPE) {
      runtime = process.env.RUNTIME_TYPE;
      detectionMethod = 'RUNTIME_TYPE env var';
    } else {
      // フォールバック: OSリリース情報から推測
      const release = os.release();
      if (release.includes('gvisor')) {
        runtime = 'gvisor';
        detectionMethod = 'os.release()';
      } else {
        runtime = 'runc';
        detectionMethod = 'fallback (assumed runc)';
      }
    }

    return c.json({
      runtime,
      detectionMethod,
      hostname: os.hostname(),
      platform: os.platform(),
      release: os.release(),
      arch: os.arch(),
      nodeVersion: process.version,
      env: {
        NODE_ENV: process.env.NODE_ENV,
        RUNTIME_TYPE: process.env.RUNTIME_TYPE
      }
    });
  } catch (error: any) {
    return c.json({
      status: 'error',
      message: error.message
    }, 500);
  }
});

export default app;
