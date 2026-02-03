import React from 'react';

const HomePage = () => {
  return (
    <div>
      <h1>Environment-Aware Builds Demo</h1>
      <p>
        <strong>API URL:</strong> {process.env.NEXT_PUBLIC_API_URL}
      </p>
    </div>
  );
};

export default HomePage;