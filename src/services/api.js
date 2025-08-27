import { useState, useCallback } from 'react';

// Standardized API error class
class ApiError extends Error {
  constructor(message, statusCode, details = {}) {
    super(message);
    this.name = 'ApiError';
    this.statusCode = statusCode;
    this.details = details;
    this.isValidationError = statusCode >= 400 && statusCode < 500;
    this.isNetworkError = !statusCode;
  }
}

// API service with standardized error handling
const createApiService = () => {
  const [toast, setToast] = useState(null);
  const [fieldErrors, setFieldErrors] = useState({});

  // Show toast notification
  const showToast = useCallback((message, type = 'error', actions = []) => {
    setToast({ id: Date.now(), message, type, actions });
  }, []);

  // Clear toast
  const clearToast = useCallback((id) => {
    setToast(prev => prev && prev.id === id ? null : prev);
  }, []);

  // Handle API response
  const handleResponse = useCallback(async (response, url) => {
    if (response.ok) {
      return response.json();
    }
    
    const contentType = response.headers.get('content-type');
    let errorData = { message: response.statusText };
    
    if (contentType && contentType.includes('application/json')) {
      try {
        errorData = await response.json();
      } catch (e) {
        // Ignore JSON parse errors
      }
    }
    
    // Network-specific errors
    if (!response.status) {
      throw new ApiError(
        'Network error. Please check your connection.',
        null,
        { url, retry: true }
      );
    }
    
    // Standard API error
    throw new ApiError(
      errorData.error?.message || errorData.message || response.statusText,
      response.status,
      {
        code: errorData.error?.code,
        details: errorData.error?.details || errorData.details,
        url
      }
    );
  }, []);

  // Standardized fetch with error handling
  const fetchWithAuth = useCallback(async (url, options = {}) => {
    try {
      const response = await fetch(url, {
        ...options,
        headers: {
          'Content-Type': 'application/json',
          ...options.headers
        }
      });
      
      return await handleResponse(response, url);
    } catch (error) {
      // Network error handling
      if (error.name === 'TypeError' && error.message === 'Failed to fetch') {
        throw new ApiError(
          'Network error. Please check your connection.',
          null,
          { url, retry: true }
        );
      }
      
      throw error;
    }
  }, [handleResponse]);

  // Form error handling
  const handleFormError = useCallback((error, setError) => {
    if (error.isValidationError && error.details.details) {
      // Clear previous field errors
      setFieldErrors({});
      
      // Set field-specific errors
      const newFieldErrors = {};
      Object.keys(error.details.details).forEach(field => {
        const message = error.details.details[field];
        newFieldErrors[field] = message;
        setError(field, { type: 'server', message });
      });
      
      setFieldErrors(newFieldErrors);
      
      // Show summary toast
      showToast(
        'Please correct the highlighted fields',
        'error',
        [{ label: 'Dismiss', action: () => setFieldErrors({}) }]
      );
      
      return true;
    }
    return false;
  }, [showToast]);

  // Global error handler
  const handleError = useCallback((error, retryCallback) => {
    if (error instanceof ApiError) {
      // Network error
      if (error.isNetworkError) {
        showToast(
          'Connection lost. Please check your network.',
          'error',
          retryCallback ? [
            { label: 'Retry', action: retryCallback },
            { label: 'Dismiss', action: () => clearToast() }
          ] : [
            { label: 'Dismiss', action: () => clearToast() }
          ]
        );
        return;
      }
      
      // Client error (4xx)
      if (error.isValidationError) {
        showToast(
          error.message || 'Please correct the form errors',
          'error',
          [{ label: 'Dismiss', action: () => clearToast() }]
        );
        return;
      }
      
      // Server error (5xx)
      showToast(
        'Something went wrong on our end. Our team has been notified.',
        'error',
        [
          { 
            label: 'Contact Support', 
            action: () => window.open('https://support.example.com', '_blank')
          },
          { label: 'Dismiss', action: () => clearToast() }
        ]
      );
      return;
    }
    
    // Unexpected JavaScript error
    showToast(
      'An unexpected error occurred',
      'error',
      [
        { 
          label: 'Contact Support', 
          action: () => window.open('https://support.example.com', '_blank')
        },
        { label: 'Dismiss', action: () => clearToast() }
      ]
    );
  }, [showToast, clearToast]);

  return {
    fetchWithAuth,
    showToast,
    clearToast,
    handleFormError,
    handleError,
    fieldErrors
  };
};

export default createApiService;