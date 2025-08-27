import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import ErrorBoundary from './components/layout/ErrorBoundary';
import Toasts from './components/feedback/Toasts';
import Header from './components/layout/Header';
import Sidebar from './components/layout/Sidebar';
import Dashboard from './pages/Dashboard';
import NewJob from './pages/NewJob';
import JobProgress from './pages/JobProgress';
import Results from './pages/Results';
import Settings from './pages/Settings';
import ThemeProvider from './context/ThemeContext';

function App() {
  return (
    <ThemeProvider>
      <ErrorBoundary>
        <Router>
          <div className="flex h-screen bg-gray-50 dark:bg-gray-900">
            <Sidebar />
            <div className="flex-1 flex flex-col overflow-hidden">
              <Header />
              <main className="flex-1 overflow-y-auto p-4 bg-gray-50 dark:bg-gray-900">
                <Routes>
                  <Route path="/" element={<Dashboard />} />
                  <Route path="/new" element={<NewJob />} />
                  <Route path="/jobs/:id/progress" element={<JobProgress />} />
                  <Route path="/jobs/:id/results" element={<Results />} />
                  <Route path="/settings" element={<Settings />} />
                </Routes>
              </main>
            </div>
            <Toasts />
          </div>
        </Router>
      </ErrorBoundary>
    </ThemeProvider>
  );
}

export default App;