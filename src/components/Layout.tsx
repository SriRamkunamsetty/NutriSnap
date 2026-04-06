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
  
  // Header (Small Title) transforms
  const headerBgOpacity = useTransform(scrollY, [40, 80], [0, 0.8]);
  const headerBorderOpacity = useTransform(scrollY, [40, 80], [0, 0.5]);
  const headerTitleOpacity = useTransform(scrollY, [60, 90], [0, 1]);
  const headerTitleY = useTransform(scrollY, [60, 90], [10, 0]);

  // Content (Large Title) transforms
  const largeTitleOpacity = useTransform(scrollY, [0, 50], [1, 0]);
  const largeTitleScale = useTransform(scrollY, [0, 50], [1, 0.95]);
  const largeTitleY = useTransform(scrollY, [0, 50], [0, -10]);

  const headerBgColor = useTransform(headerBgOpacity, (o) => `rgba(248, 249, 251, ${o})`);
  const headerBorderColor = useTransform(headerBorderOpacity, (o) => `rgba(243, 244, 246, ${o})`);
  const headerBlur = useTransform(headerBgOpacity, (o) => `blur(${o * 12}px)`);

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
              backgroundColor: headerBgColor,
              borderBottomColor: headerBorderColor,
              backdropFilter: headerBlur
            }}
            className="px-6 py-2 flex items-center justify-between sticky top-0 z-40 border-b"
          >
            <div className="flex items-center gap-3">
              <motion.div 
                style={{ opacity: headerTitleOpacity, y: headerTitleY }}
                className="flex items-center gap-2"
              >
                <div className="w-8 h-8 bg-green-500 rounded-xl flex items-center justify-center shadow-lg shadow-green-500/20">
                  <span className="text-white font-bold text-lg tracking-tighter">N</span>
                </div>
                <AnimatePresence mode="wait">
                  <motion.h1 
                    key={title}
                    initial={{ opacity: 0, x: -10 }}
                    animate={{ opacity: 1, x: 0 }}
                    exit={{ opacity: 0, x: 10 }}
                    transition={{ duration: 0.2 }}
                    className="text-lg font-bold text-gray-900 tracking-tight"
                  >
                    {title}
                  </motion.h1>
                </AnimatePresence>
              </motion.div>
            </div>
            <motion.div 
              style={{ opacity: headerTitleOpacity }}
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
      <main className={cn("flex-1 pb-32", isHome ? "pt-4" : "pt-0")}>
        <div className="max-w-md mx-auto w-full px-4 overflow-x-hidden">
          <AnimatePresence mode="wait">
            {!isHome && title && (
              <motion.div
                key={`title-${location.pathname}`}
                style={{ 
                  opacity: largeTitleOpacity, 
                  scale: largeTitleScale, 
                  y: largeTitleY 
                }}
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -10 }}
                className="mb-1 px-2 relative z-10"
              >
                <h2 className="text-5xl font-black text-gray-900 tracking-tighter">{title}</h2>
              </motion.div>
            )}
          </AnimatePresence>

          <AnimatePresence mode="wait">
            <motion.div
              key={location.pathname}
              initial={{ opacity: 0, x: 10 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -10 }}
              transition={{ duration: 0.3, ease: "easeOut" }}
            >
              <Outlet />
            </motion.div>
          </AnimatePresence>
        </div>
      </main>

      {/* Floating Pill Navigation - Liquid Glass Style */}
      <div className="fixed bottom-8 left-0 right-0 z-50 px-8 pointer-events-none">
        <nav className="max-w-[320px] mx-auto bg-white/40 backdrop-blur-2xl rounded-[32px] p-1 flex justify-around items-center pointer-events-auto border border-white/40 shadow-[0_8px_32px_rgba(0,0,0,0.08)] relative h-14">
          {navItems.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              onClick={() => triggerHaptic(hapticPatterns.light)}
              className={({ isActive }) =>
                cn(
                  "relative flex items-center justify-center w-12 h-10 rounded-2xl transition-colors duration-300 ease-out ios-tap",
                  isActive ? "text-green-600" : "text-gray-400 hover:text-gray-600"
                )
              }
            >
              {({ isActive }) => (
                <>
                  {isActive && (
                    <motion.div
                      layoutId="liquid-pill"
                      className="absolute inset-0 bg-white shadow-[0_2px_8px_rgba(0,0,0,0.04)] rounded-xl"
                      transition={{ 
                        type: "spring", 
                        stiffness: 400, 
                        damping: 32,
                        mass: 0.8
                      }}
                    />
                  )}
                  <item.icon 
                    size={20} 
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
