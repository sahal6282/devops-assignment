import { Logger, registerWorker } from 'iii-sdk';

const INFERENCE_URL = process.env.III_URL || 'ws://10.0.2.198:49134';

const iii = registerWorker(INFERENCE_URL);
const logger = new Logger();

iii.registerFunction(
  'inference::get_response',
  async (payload: any) => {
    logger.info('inference::get_response called', payload);

    const result = await iii.trigger({
      function_id: 'inference::run_inference',
      payload,
    });

    const typedResult = result as Record<string, any>;

    return {
      ...typedResult,
      success: true,
      message: "Caller → Inference pipeline working",
    };
  }
);

iii.registerFunction(
  'http::run_inference_over_http',
  async (payload: any) => {
    logger.info('HTTP inference request received');

    const result = await iii.trigger({
      function_id: 'inference::get_response',
      payload: payload.body,
    });

    return {
      status_code: 200,
      body: result,
      headers: { 'Content-Type': 'application/json' },
    };
  }
);

iii.registerTrigger({
  type: 'http',
  function_id: 'http::run_inference_over_http',
  config: {
    api_path: '/v1/chat/completions',
    http_method: 'POST',
  },
});

logger.info('Caller worker started successfully');
