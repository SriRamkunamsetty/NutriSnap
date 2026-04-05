import React, { useState, useEffect } from 'react';
import { NavLink, Outlet, useLocation } from 'react-router-dom';
import { Home, History, BarChart2, MessageSquare, Settings, User } from 'lucide-react';
import { motion, AnimatePresence, useScroll, useTransform } from 'motion/react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { useUser } from '../contexts/UserContext';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

const titles: Record<string, string> = {
  '/history': 'History',
  '/analytics': 'Analytics',
  '/chat': 'AI Coach',
  '/settings': 'Settings',
};

const Layout: React.FC = () => {
  const { profile } = useUser();
  const location = useLocation();
  const isHome = location.pathname === '/';
  const title = titles[location.pathname] || '';

  const { scrollY } = useScroll();
  const headerBgOpacity = useTransform(scrollY, [20, 60], [0, 0.8]);
  const headerBorderOpacity = useTransform(scrollY, [20, 60], [0, 0.5]);
  const headerOpacity = useTransform(scrollY, [20, 60], [0, 1]);
  const headerY = useTransform(scrollY, [20, 60], [10, 0]);

  const navItems = [
    { to: '/', icon: Home, label: 'Home' },
    { to: '/history', icon: History, label: 'History' },
    { to: '/analytics', icon: BarChart2, label: 'Stats' },
    { to: '/chat', icon: MessageSquare, label: 'AI' },
    { to: '/settings', icon: Settings, label: 'Settings' },
  ];

  return (
    <div className="flex flex-col min-h-screen bg-[#F8F9FB] font-sans selection:bg-green-100">
      {/* Header - iOS Style Collapsing */}
      <AnimatePresence mode="wait">
        {!isHome && (
          <motion.header 
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            style={{ 
              backgroundColor: useTransform(headerBgOpacity, (o) => `rgba(248, 249, 251, ${o})`),
              borderBottomColor: useTransform(headerBorderOpacity, (o) => `rgba(243, 244, 246, ${o})`),
              backdropFilter: useTransform(headerBgOpacity, (o) => `blur(${o * 12}px)`)
            }}
            className="px-6 py-4 flex items-center justify-between sticky top-0 z-40 border-b"
          >
            <div className="flex items-center gap-3">
              <motion.div 
                style={{ opacity: headerOpacity, y: headerY }}
                className="flex items-center gap-2"
              >
                <div className="w-8 h-8 bg-green-500 rounded-xl flex items-center justify-center shadow-lg shadow-green-500/20">
                  <span className="text-white font-bold text-lg tracking-tighter">N</span>
                </div>
                <h1 className="text-lg font-bold text-gray-900 tracking-tight">{title}</h1>
              </motion.div>
            </div>
            <motion.div 
              style={{ opacity: headerOpacity }}
              className="w-10 h-10 rounded-full bg-white border border-gray-100 flex items-center justify-center shadow-sm overflow-hidden relative ios-tap"
            >
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
            </motion.div>
          </motion.header>
        )}
      </AnimatePresence>

      {/* Main Content */}
      <main className={cn("flex-1 pb-32", !isHome && "pt-4")}>
        <div className="max-w-md mx-auto w-full px-4">
          <AnimatePresence mode="wait">
            {!isHome && title && (
              <motion.div
                key={location.pathname}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -20 }}
                className="mb-8 px-2"
              >
                <h2 className="text-4xl font-black text-gray-900 tracking-tighter">{title}</h2>
              </motion.div>
            )}
          </AnimatePresence>
          <Outlet />
        </div>
      </main>

      {/* Floating Pill Navigation - Liquid Glass Style */}
      <div className="fixed bottom-8 left-0 right-0 z-50 px-6 pointer-events-none">
        <nav className="max-w-sm mx-auto glass rounded-full p-1.5 flex justify-around items-center pointer-events-auto ios-shadow relative h-16">
          {navItems.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              onClick={() => triggerHaptic(hapticPatterns.light)}
              className={({ isActive }) =>
                cn(
                  "relative flex flex-col items-center justify-center w-14 h-12 rounded-2xl transition-all duration-500 ease-out ios-tap",
                  isActive ? "text-green-600" : "text-gray-400 hover:text-gray-600"
                )
              }
            >
              {({ isActive }) => (
                <>
                  {isActive && (
                    <motion.div
                      layoutId="active-pill"
                      className="absolute inset-0 bg-green-500/10 rounded-2xl"
                      transition={{ 
                        type: "spring", 
                        stiffness: 380, 
                        damping: 30,
                        mass: 1
                      }}
                    />
                  )}
                  <item.icon 
                    size={22} 
                    strokeWidth={isActive ? 2.5 : 2} 
                    className="relative z-10"
                  />
                </>
              )}
            </NavLink>
          ))}
        </nav>
      </div>
    </div>
  );
};

export default Layout;
