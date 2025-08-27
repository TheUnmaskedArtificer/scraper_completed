import React, { Component } from 'react';
import Toasts from '../feedback/Toasts';

class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { 
      hasError: false,
      error: null,
      errorInfo: null,
      toast: null
    };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }

  componentDidCatch(error, errorInfo) {
    this.setState({
      errorInfo,
      toast: {
        message: 'Something went wrong. Our team has been notified.',
        type: 'error',
        actions: [
          { 
            label: 'Contact Support', 
            action: () => window.open('https://support.example.com', '_blank')
          },
          { 
            label: 'Refresh Page', 
            action: () => window.location.reload() 
          }
        ]
      }
    });
    
    // Log error to monitoring service (placeholder)
    console.error('ErrorBoundary caught an error', error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="min-h-screen flex flex-col">
          <main className="flex-grow container mx-auto px-4 py-8 max-w-2xl">
            <div 
              className="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg p-6"
              role="alert"
              aria-labelledby="error-heading"
            >
              <h2 id="error-heading" className="text-xl font-bold text-red-800 dark:text-red-200 mb-2">
                Application Error
              </h2>
              <p className="text-red-700 dark:text-red-300 mb-4">
                An unexpected error has occurred. Please try refreshing the page or contact support.
              </p>
              
              <details className="mb-4">
                <summary className="cursor-pointer text-sm text-red-600 dark:text-red-400 hover:underline">
                  Show error details
                </summary>
                <pre className="mt-2 p-3 bg-red-100 dark:bg-red-900/30 rounded text-sm text-red-800 dark:text-red-200 overflow-auto max-h-40">
                  {this.state.error && this.state.error.toString()}
                </pre>
              </details>
              
              <div className="flex flex-wrap gap-2">
                <button
                  onClick={() => window.location.reload()}
                  className="px-4 py-2 bg-red-100 text-red-800 rounded-md hover:bg-red-200 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 dark:bg-red-900/50 dark:text-red-200 dark:hover:bg-red-900/70"
                  aria-label="Refresh the page to try again"
                >
                  Refresh Page
                </button>
                <button
                  onClick={() => window.open('https://support.example.com', '_blank')}
                  className="px-4 py-2 bg-gray-100 text-gray-800 rounded-md hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-gray-500 focus:ring-offset-2 dark:bg-gray-800 dark:text-gray-200 dark:hover:bg-gray-700"
                  aria-label="Contact support for help"
                >
                  Contact Support
                </button>
              </div>
            </div>
          </main>
          
          {this.state.toast && (
            <Toasts 
              message={this.state.toast.message} 
              type={this.state.toast.type}
              actions={this.state.toast.actions}
            />
          )}
        </div>
      );
    }

    return this.props.children; 
  }
}

export default ErrorBoundary;