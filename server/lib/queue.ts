import PQueue from 'p-queue';

// Create queue with concurrency limit of 3 workers
const queue = new PQueue({ concurrency: 3 });

/**
 * Enqueue a job for processing
 * @param jobId - Unique identifier for the job
 * @param workFn - Async function containing the work to be performed
 */
export const enqueue = (jobId: string, workFn: () => Promise<void>) => {
  queue.add(async () => {
    try {
      await workFn();
    } catch (error) {
      console.error(`[Queue] Job ${jobId} failed:`, error);
      // Error handling would typically update job status in DB
      throw error;
    }
  });
};

// Export queue instance for monitoring/debugging
export default queue;