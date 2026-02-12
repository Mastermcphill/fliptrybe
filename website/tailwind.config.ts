import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./app/**/*.{js,ts,jsx,tsx}', './components/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        brand: {
          50: '#ecfeff',
          500: '#06b6d4',
          700: '#0e7490',
          900: '#164e63'
        }
      }
    }
  },
  plugins: []
};

export default config;
