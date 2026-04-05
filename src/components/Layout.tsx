import React from 'react';
import { NavLink, Outlet } from 'react-router-dom';
import { Home, History, BarChart2, MessageSquare, Settings, User } from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { useUser } from '../contexts/UserContext';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

const Layout: React.FC = () => {
  const { profile } = useUser();
  const navItems = [
    { to: '/', icon: Home, label: 'Home' },
    { to: '/history', icon: History, label: 'History' },
    { to: '/analytics', icon: BarChart2, label: 'Stats' },
    { to: '/chat', icon: MessageSquare, label: 'AI' },
    { to: '/settings', icon: Settings, label: 'Settings' },
  ];

  return (
    <div className="flex flex-col min-h-screen bg-[#F8F9FB] font-sans selection:bg-green-100">
      {/* Header - Minimal & Elegant */}
      <header className="px-6 py-6 flex items-center justify-between sticky top-0 z-40 bg-[#F8F9FB]/80 backdrop-blur-md">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-green-500 rounded-2xl flex items-center justify-center shadow-lg shadow-green-500/20">
            <span className="text-white font-bold text-2xl tracking-tighter">N</span>
          </div>
          <h1 className="text-xl font-bold text-gray-900 tracking-tight">NutriSnap</h1>
        </div>
        <div className="w-10 h-10 rounded-full bg-white border border-gray-100 flex items-center justify-center shadow-sm overflow-hidden relative">
          {profile?.photoURL ? (
            <img 
              src={profile.photoURL} 
              alt="Profile" 
              className="w-full h-full object-cover"
              referrerPolicy="no-referrer"
            />
          ) : (
            <User size={18} className="text-gray-400" />
          )}
          <div className="absolute bottom-0 right-0 w-2.5 h-2.5 bg-green-500 rounded-full border-2 border-white animate-pulse" />
        </div>
      </header>

      {/* Main Content */}
      <main className="flex-1 pb-32">
        <div className="max-w-md mx-auto w-full px-4">
          <Outlet />
        </div>
      </main>

      {/* Floating Pill Navigation */}
      <div className="fixed bottom-8 left-0 right-0 z-50 px-6 pointer-events-none">
        <nav className="max-w-sm mx-auto glass rounded-[32px] p-2 flex justify-around items-center pointer-events-auto ios-shadow">
          {navItems.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              onClick={() => triggerHaptic(hapticPatterns.light)}
              className={({ isActive }) =>
                cn(
                  "relative flex flex-col items-center justify-center w-14 h-14 rounded-2xl transition-all duration-500 ease-out",
                  isActive 
                    ? "text-green-600 bg-green-50/80 scale-105 shadow-sm" 
                    : "text-gray-400 hover:text-gray-600 hover:bg-gray-50/50"
                )
              }
            >
              {({ isActive }) => (
                <item.icon size={22} strokeWidth={isActive ? 2.5 : 2} />
              )}
            </NavLink>
          ))}
        </nav>
      </div>
    </div>
  );
};

export default Layout;
