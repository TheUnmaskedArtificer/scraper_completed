import React, { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import Toasts from '../components/feedback/Toasts';
import FileTreePreview from '../components/job/FileTreePreview';
import ReactMarkdown from 'react-markdown';
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter';
import { vscDarkPlus } from 'react-syntax-highlighter/dist/esm/styles/prism';

const Results = () => {
  const { id } = useParams<{ id: string }>();
  const [toast, setToast] = useState<{ message: string; type: 'success' | 'error' } | null>(null);
  const [results, setResults] = useState<{ name: string; url: string; type: string; size?: number }[]>([]);
  const [selectedFile, setSelectedFile] = useState<{ name: string; url: string; content: string } | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [format, setFormat] = useState<'rag' | 'markdown' | null>(null);
  const [isDownloading, setIsDownloading] = useState<boolean>(false);
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [searchLimit, setSearchLimit] = useState<number>(8);
  const [searching, setSearching] = useState<boolean>(false);
  const [hits, setHits] = useState<{ score: number; name: string; url: string; text_snippet: string }[]>([]);

  useEffect(() => {
    const fetchResults = async () => {
      if (!id) return;
      
      try {
        setIsLoading(true);
        const response = await fetch(`${import.meta.env.VITE_API_URL}/api/jobs/${id}/results`);
        
        if (!response.ok) {
          throw new Error('Failed to fetch results');
        }
        
        const data = await response.json();
        setResults(data.files);
        
        // Determine format based on file patterns
        const hasRagFile = data.files.some(file => file.name === 'rag_export.jsonl');
        setFormat(hasRagFile ? 'rag' : 'markdown');
      } catch (error) {
        setToast({ 
          message: error instanceof Error ? error.message : 'Failed to load results', 
          type: 'error' 
        });
      } finally {
        setIsLoading(false);
      }
    };
    
    fetchResults();
  }, [id]);

  // Auto-load RAG export content when available
  useEffect(() => {
    if (format !== 'rag') return;
    const ragFile = results.find(file => file.name === 'rag_export.jsonl');
    if (!ragFile) return;

    (async () => {
      try {
        const response = await fetch(ragFile.url);
        if (!response.ok) throw new Error('Failed to fetch RAG file');
        const content = await response.text();
        setSelectedFile({ name: ragFile.name, url: ragFile.url, content });
      } catch (error) {
        setToast({
          message: error instanceof Error ? error.message : 'Failed to load RAG file',
          type: 'error'
        });
      }
    })();
  }, [format, results]);

  const handleCopyUrl = async (url: string) => {
    try {
      await navigator.clipboard.writeText(url);
      setToast({ message: 'URL copied to clipboard', type: 'success' });
    } catch (error) {
      setToast({ message: 'Failed to copy URL', type: 'error' });
    }
  };

  const handleCopyText = async (text: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setToast({ message: 'Text copied to clipboard', type: 'success' });
    } catch (error) {
      setToast({ message: 'Failed to copy text', type: 'error' });
    }
  };

  const handleFileClick = async (file: { name: string; url: string }) => {
    try {
      const response = await fetch(file.url);
      if (!response.ok) throw new Error('Failed to fetch file content');
      
      const content = await response.text();
      setSelectedFile({ ...file, content });
    } catch (error) {
      setToast({
        message: error instanceof Error ? error.message : 'Failed to load file',
        type: 'error'
      });
    }
  };

  const handleSearch = async () => {
    if (!searchQuery.trim()) {
      setToast({ message: 'Enter a query to search', type: 'error' });
      return;
    }
    setSearching(true);
    try {
      const response = await fetch(`${import.meta.env.VITE_API_URL}/api/search`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          query: searchQuery,
          jobId: id,
          limit: searchLimit
        })
      });
      if (!response.ok) throw new Error('Search failed');
      const data = await response.json();
      setHits(data.hits || data.results || []);
    } catch (error) {
      setToast({
        message: error instanceof Error ? error.message : 'Search failed',
        type: 'error'
      });
    } finally {
      setSearching(false);
    }
  };

  const renderSearchPanel = () => (
    <div className="mb-6 rounded-lg border border-gray-200 dark:border-gray-700 p-4 bg-white dark:bg-gray-800">
      <h2 className="text-lg font-medium text-gray-900 dark:text-white mb-3">Semantic Search</h2>
      <div className="flex flex-col sm:flex-row sm:items-center gap-3">
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder="Enter a question or keywords..."
          className="flex-1 rounded-md border px-3 py-2 shadow-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm dark:bg-gray-700 dark:text-white dark:border-gray-600"
        />
        <input
          type="number"
          min={1}
          max={20}
          value={searchLimit}
          onChange={(e) => setSearchLimit(Math.max(1, Math.min(20, Number(e.target.value) || 8)))}
          className="w-24 rounded-md border px-3 py-2 shadow-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm dark:bg-gray-700 dark:text-white dark:border-gray-600"
          aria-label="Top K"
          title="Top K results"
        />
        <button
          onClick={handleSearch}
          disabled={searching}
          className="px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50"
        >
          {searching ? 'Searching...' : 'Search'}
        </button>
      </div>

      {hits.length > 0 && (
        <div className="mt-4 space-y-3">
          {hits.map((h, idx) => (
            <div key={idx} className="p-3 rounded-md bg-gray-50 dark:bg-gray-900 border border-gray-200 dark:border-gray-700">
              <div className="flex justify-between items-center">
                <div className="text-sm text-gray-600 dark:text-gray-400">Score: {typeof h.score === 'number' ? h.score.toFixed(3) : h.score}</div>
                <div className="space-x-2">
                  {h.url && (
                    <button
                      onClick={() => handleCopyUrl(h.url)}
                      className="text-xs px-2 py-1 bg-indigo-100 text-indigo-700 rounded hover:bg-indigo-200 dark:bg-indigo-900 dark:text-indigo-300"
                    >
                      Copy URL
                    </button>
                  )}
                  {h.text_snippet && (
                    <button
                      onClick={() => handleCopyText(h.text_snippet)}
                      className="text-xs px-2 py-1 bg-gray-200 text-gray-800 rounded hover:bg-gray-300 dark:bg-gray-700 dark:text-gray-100"
                    >
                      Copy Snippet
                    </button>
                  )}
                </div>
              </div>
              <div className="mt-2 text-sm">
                <span className="font-medium text-gray-900 dark:text-white">{h.name || 'Result'}</span>
              </div>
              {h.text_snippet && (
                <p className="mt-1 text-sm text-gray-700 dark:text-gray-300 line-clamp-4">
                  {h.text_snippet}
                </p>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );

  const handleDownloadAll = async () => {
    if (!id) return;
    
    setIsDownloading(true);
    try {
      const response = await fetch(`${import.meta.env.VITE_API_URL}/api/jobs/${id}/download`, {
        method: 'GET',
      });
      
      if (!response.ok) {
        throw new Error('Failed to download results');
      }
      
      const blob = await response.blob();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `job_${id}_results.zip`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      window.URL.revokeObjectURL(url);
      
      setToast({ message: 'Download started', type: 'success' });
    } catch (error) {
      setToast({ 
        message: error instanceof Error ? error.message : 'Failed to download results', 
        type: 'error' 
      });
    } finally {
      setIsDownloading(false);
    }
  };

  const renderRagView = () => {
    const ragFile = results.find(file => file.name === 'rag_export.jsonl');
    if (!ragFile) return <div className="text-center py-8 text-gray-500">RAG file not found</div>;
    
    return (
      <div className="space-y-4">
        <div className="flex justify-between items-center">
          <h2 className="text-lg font-medium text-gray-900 dark:text-white">RAG Export</h2>
          <div className="flex space-x-2">
            <button
              onClick={() => handleCopyUrl(ragFile.url)}
              className="px-2 py-1 text-sm text-indigo-600 hover:text-indigo-800 dark:text-indigo-400 dark:hover:text-indigo-200"
              aria-label="Copy RAG file URL"
            >
              Copy URL
            </button>
            <a
              href={ragFile.url}
              download
              className="px-2 py-1 text-sm bg-indigo-100 text-indigo-700 rounded-md hover:bg-indigo-200 dark:bg-indigo-900 dark:text-indigo-300 dark:hover:bg-indigo-800"
            >
              Download
            </a>
          </div>
        </div>
        
        <div className="bg-gray-50 dark:bg-gray-800 rounded-lg overflow-hidden">
          <SyntaxHighlighter
            language="json"
            style={vscDarkPlus}
            className="text-sm"
          >
            {selectedFile?.content || 'Loading...'}
          </SyntaxHighlighter>
        </div>
      </div>
    );
  };

  const renderMarkdownView = () => {
    return (
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-1">
          <h2 className="text-lg font-medium text-gray-900 dark:text-white mb-3">Files</h2>
          <FileTreePreview 
            files={results} 
            onFileClick={handleFileClick}
            onCopyUrl={handleCopyUrl}
          />
          
          <button
            onClick={handleDownloadAll}
            disabled={isDownloading}
            className="mt-4 w-full px-4 py-2 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50"
          >
            {isDownloading ? 'Downloading...' : 'Download All (.zip)'}
          </button>
        </div>
        
        <div className="lg:col-span-2">
          {selectedFile ? (
            <>
              <div className="flex justify-between items-center mb-3">
                <h2 className="text-lg font-medium text-gray-900 dark:text-white">
                  {selectedFile.name}
                </h2>
                <button
                  onClick={() => handleCopyUrl(selectedFile.url)}
                  className="px-2 py-1 text-sm text-indigo-600 hover:text-indigo-800 dark:text-indigo-400 dark:hover:text-indigo-200"
                >
                  Copy URL
                </button>
              </div>
              
              <div className="bg-gray-50 dark:bg-gray-800 rounded-lg p-4 overflow-auto max-h-[70vh]">
                <ReactMarkdown
                  className="prose dark:prose-invert max-w-none"
                  components={{
                    code({ node, inline, className, children, ...props }) {
                      const match = /language-(\w+)/.exec(className || '');
                      return !inline && match ? (
                        <SyntaxHighlighter
                          style={vscDarkPlus}
                          language={match[1]}
                          PreTag="div"
                          {...props}
                        >
                          {String(children).replace(/\n$/, '')}
                        </SyntaxHighlighter>
                      ) : (
                        <code className={className} {...props}>
                          {children}
                        </code>
                      );
                    }
                  }}
                >
                  {selectedFile.content}
                </ReactMarkdown>
              </div>
            </>
          ) : (
            <div className="flex items-center justify-center h-[70vh] bg-gray-50 dark:bg-gray-800 rounded-lg">
              <p className="text-gray-500 dark:text-gray-400">
                Select a file to preview
              </p>
            </div>
          )}
        </div>
      </div>
    );
  };

  if (isLoading) {
    return (
      <div className="container mx-auto px-4 py-8 max-w-3xl">
        <div className="animate-pulse space-y-4">
          <div className="h-8 bg-gray-200 rounded dark:bg-gray-700 w-3/4"></div>
          <div className="h-4 bg-gray-200 rounded dark:bg-gray-700 w-1/2"></div>
          <div className="h-64 bg-gray-200 rounded dark:bg-gray-700"></div>
        </div>
      </div>
    );
  }

  if (results.length === 0) {
    return (
      <div className="container mx-auto px-4 py-8 max-w-3xl">
        <div className="text-center py-12">
          <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-4">
            No Results Found
          </h2>
          <p className="text-gray-600 dark:text-gray-400">
            The job completed but no results were generated.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-8 max-w-6xl">
      {toast && (
        <Toasts 
          message={toast.message} 
          type={toast.type} 
          onClose={() => setToast(null)} 
        />
      )}
      
      <div className="flex justify-between items-center mb-8">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">
          Results for Job: {id}
        </h1>
      </div>
      
      {format === 'rag' && renderSearchPanel()}
      {format === 'rag' ? renderRagView() : renderMarkdownView()}
    </div>
  );
};

export default Results;