import { installBridge } from './bridge';

if (typeof window !== 'undefined') installBridge(window);
