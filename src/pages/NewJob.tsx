import React, { useState } from 'react';
import { useForm, Controller } from 'react-hook-form';
import { useNavigate } from 'react-router-dom';
import useApiService from '../services/api';
import Toasts from '../components/feedback/Toasts';

type FormData = {
  urls: string;
  type: 'docs' | 'repo';
  depth: number;
  maxPages: number;
  format: 'rag' | 'markdown';
};

const NewJob = () => {
  const [toast, setToast] = useState<{ message: string; type: 'success' | 'error' } | null>(null);
  const navigate = useNavigate();
  const { fetchWithAuth, handleError, handleFormError } = useApiService();
  
  const { control, handleSubmit, setError, formState: { errors, isSubmitting } } = useForm<FormData>({
    defaultValues: {
      type: 'docs',
      depth: 3,
      maxPages: 100,
      format: 'rag'
    }
  });

  const onSubmit = async (data: FormData) => {
    // Process URLs (trim and filter empty lines)
    const urls = data.urls
      .split('\n')
      .map(url => url.trim())
      .filter(url => url);
    
    if (urls.length === 0) {
      setToast({ message: 'Please enter at least one valid URL', type: 'error' });
      return;
    }

    // Coerce numeric values with fallback defaults
    const depth = Number(data.depth) || 3;
    const maxPages = Number(data.maxPages) || 100;

    try {
      const response = await fetchWithAuth(`${import.meta.env.VITE_API_URL}/api/jobs`, {
        method: 'POST',
        body: JSON.stringify({
          urls,
          type: data.type,
          depth,
          maxPages,
          format: data.format
        })
      });

      const { jobId } = response;
      setToast({ message: 'Job created successfully!', type: 'success' });
      setTimeout(() => navigate(`/jobs/${jobId}/progress`), 1000);
    } catch (error) {
      if (!handleFormError(error, setError)) {
        handleError(error, () => onSubmit(data));
      }
    }
  };

  return (
    <div className="container mx-auto px-4 py-8 max-w-2xl">
      {toast && <Toasts message={toast.message} type={toast.type} onClose={() => setToast(null)} />}
      
      <h1 className="text-2xl font-bold mb-6 text-gray-900 dark:text-white">
        New Scraping Job
      </h1>
      
      <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
        {/* Target URLs */}
        <div>
          <label 
            htmlFor="urls" 
            className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1"
            aria-required="true"
          >
            Target URLs (one per line)
          </label>
          <Controller
            name="urls"
            control={control}
            rules={{ required: true }}
            render={({ field }) => (
              <textarea
                {...field}
                id="urls"
                rows={4}
                className={`w-full rounded-md border px-3 py-2 shadow-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm ${
                  errors.urls ? 'border-red-500' : 'border-gray-300 dark:border-gray-600'
                } dark:bg-gray-700 dark:text-white`}
                placeholder="https://example.com\nhttps://another.com"
                aria-invalid={errors.urls ? 'true' : 'false'}
                aria-errormessage={errors.urls ? 'urls-error' : undefined}
              />
            )}
          />
          {errors.urls && (
            <p id="urls-error" className="mt-1 text-sm text-red-600 dark:text-red-400">
              Please enter at least one URL
            </p>
          )}
        </div>

        {/* Scrape Type */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Scrape Type
          </label>
          <div className="flex space-x-6">
            <label className="flex items-center">
              <Controller
                name="type"
                control={control}
                render={({ field }) => (
                  <input
                    {...field}
                    type="radio"
                    value="docs"
                    checked={field.value === 'docs'}
                    className="text-indigo-600 focus:ring-indigo-500 h-4 w-4"
                    aria-label="Scrape as documentation"
                  />
                )}
              />
              <span className="ml-2 text-gray-700 dark:text-gray-300">Docs</span>
            </label>
            
            <label className="flex items-center">
              <Controller
                name="type"
                control={control}
                render={({ field }) => (
                  <input
                    {...field}
                    type="radio"
                    value="repo"
                    checked={field.value === 'repo'}
                    className="text-indigo-600 focus:ring-indigo-500 h-4 w-4"
                    aria-label="Scrape GitHub repository"
                  />
                )}
              />
              <span className="ml-2 text-gray-700 dark:text-gray-300">GitHub repo</span>
            </label>
          </div>
        </div>

        {/* Depth Slider */}
        <div>
          <label 
            htmlFor="depth" 
            className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1"
          >
            Depth (1-10)
          </label>
          <div className="flex items-center space-x-4">
            <Controller
              name="depth"
              control={control}
              render={({ field }) => (
                <>
                  <input
                    {...field}
                    type="range"
                    min="1"
                    max="10"
                    className="w-full h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer dark:bg-gray-700"
                    aria-valuemin="1"
                    aria-valuemax="10"
                    aria-valuenow={field.value}
                  />
                  <span className="w-12 text-center text-gray-900 dark:text-white">
                    {field.value}
                  </span>
                </>
              )}
            />
          </div>
        </div>

        {/* Max Pages */}
        <div>
          <label 
            htmlFor="maxPages" 
            className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1"
          >
            Max Pages
          </label>
          <Controller
            name="maxPages"
            control={control}
            render={({ field }) => (
              <input
                {...field}
                type="number"
                min="1"
                className="mt-1 block w-32 rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                aria-label="Maximum number of pages to scrape"
              />
            )}
          />
        </div>

        {/* Output Format */}
        <div>
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
            Output Format
          </label>
          <div className="flex space-x-6">
            <label className="flex items-center">
              <Controller
                name="format"
                control={control}
                render={({ field }) => (
                  <input
                    {...field}
                    type="radio"
                    value="rag"
                    checked={field.value === 'rag'}
                    className="text-indigo-600 focus:ring-indigo-500 h-4 w-4"
                    aria-label="Output in RAG JSONL format"
                  />
                )}
              />
              <span className="ml-2 text-gray-700 dark:text-gray-300">RAG JSONL</span>
            </label>
            
            <label className="flex items-center">
              <Controller
                name="format"
                control={control}
                render={({ field }) => (
                  <input
                    {...field}
                    type="radio"
                    value="markdown"
                    checked={field.value === 'markdown'}
                    className="text-indigo-600 focus:ring-indigo-500 h-4 w-4"
                    aria-label="Output in Markdown format"
                  />
                )}
              />
              <span className="ml-2 text-gray-700 dark:text-gray-300">Markdown</span>
            </label>
          </div>
        </div>

        <button
          type="submit"
          disabled={isSubmitting}
          className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50"
        >
          {isSubmitting ? 'Creating Job...' : 'Start Scraping'}
        </button>
      </form>
    </div>
  );
};

export default NewJob;