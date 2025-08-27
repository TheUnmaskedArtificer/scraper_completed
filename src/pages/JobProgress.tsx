import React, { useState, useEffect, useRef } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import Toasts from '../components/feedback/Toasts';
import LogsPane from '../components/realtime/LogsPane';

const JobProgress = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const logsEndRef = useRef<HTMLDivElement>(null);
  const [toast, setToast] = useState<{ message: string; type: 'success' | 'error' } | null>(null);
  const [jobStatus, setJobStatus] = useState<{
    status: 'queued' | 'running' | 'failed' | 'completed';
    progress: number;
    logs: string[];
  }>({
    status: 'queued',
    progress: 0,
    logs: []
  });
  
  const [pollingInterval, setPollingInterval] = useState<number>(1000);
  const [isPolling, setIsPolling] = useState<boolean>(true);
  // Cancel not supported by API; button removed

  // Auto-scroll to bottom of logs
  useEffect(() => {
    logsEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [jobStatus.logs]);

  // Poll job status
  useEffect(() => {
    if (!isPolling || !id) return;
    
    let retryCount = 0;
    const maxRetries = 5;
    const maxInterval = 10000; // 10 seconds max
    
    const pollStatus = async () => {
      try {
        const response = await fetch(`${import.meta.env.VITE_API_URL}/api/jobs/${id}/status`);
        
        if (!response.ok) {
          throw new Error('Status fetch failed');
        }
        
        const data = await response.json();
        setJobStatus(data);
        
        // Reset progress on running status
        if (data.status === 'running' && data.progress === 0) {
          setPollingInterval(1000);
        }
        
        // Stop polling if job completed/failed
        if (data.status === 'completed' || data.status === 'failed') {
          setIsPolling(false);
        }
        
      } catch (error) {
        retryCount++;
        setToast({ 
          message: error instanceof Error ? error.message : 'Connection error', 
          type: 'error' 
        });
        
        // Exponential backoff
        if (retryCount < maxRetries) {
          const newInterval = Math.min(pollingInterval * 1.5, maxInterval);
          setPollingInterval(newInterval);
        } else {
          setIsPolling(false);
        }
      }
    };
    
    const intervalId = setInterval(pollStatus, pollingInterval);
    return () => clearInterval(intervalId);
  }, [isPolling, pollingInterval, id]);

  // Cancel endpoint not available; removing handler

  const getStatusColor = () => {
    switch (jobStatus.status) {
      case 'queued': return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-300';
      case 'running': return 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-300';
      case 'failed': return 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-300';
      case 'completed': return 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-300';
      default: return '';
    }
  };

  return (
    <div className="container mx-auto px-4 py-8 max-w-3xl">
      {toast && (
        <Toasts 
          message={toast.message} 
          type={toast.type} 
          onClose={() => setToast(null)} 
        />
      )}
      
      <div className="flex justify-between items-center mb-8">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">
          Job Progress: {id}
        </h1>
        
        {jobStatus.status === 'completed' && (
          <button
            onClick={() => navigate(`/jobs/${id}/results`)}
            className="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:focus:ring-offset-gray-800"
          >
            View Results
          </button>
        )}
      </div>

      {/* Status Pill */}
      <div className="mb-6">
        <span className={`inline-flex items-center px-3 py-0.5 rounded-full text-sm font-medium ${getStatusColor()}`}>
          {jobStatus.status.charAt(0).toUpperCase() + jobStatus.status.slice(1)}
        </span>
      </div>

      {/* Progress Bar */}
      <div className="mb-8">
        <div className="w-full bg-gray-200 rounded-full h-2.5 dark:bg-gray-700">
          <div 
            className="bg-indigo-600 h-2.5 rounded-full transition-all duration-300 ease-in-out" 
            style={{ width: `${jobStatus.progress}%` }}
          ></div>
        </div>
        <div className="mt-2 text-right text-sm text-gray-600 dark:text-gray-400">
          {jobStatus.progress}%
        </div>
      </div>

      {/* Logs */}
      <div className="mb-8">
        <h2 className="text-lg font-medium text-gray-900 dark:text-white mb-3">
          Real-time Logs
        </h2>
        <LogsPane logs={jobStatus.logs} />
        <div ref={logsEndRef} />
      </div>

      {/* Cancel controls removed: API lacks cancel endpoint */}
    </div>
  );
};

export default JobProgress;