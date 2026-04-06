import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Search, Filter, ChevronRight, Calendar, Apple, X } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { format, isWithinInterval, startOfDay, endOfDay } from 'date-fns';
import { useUser } from '../contexts/UserContext';
import { ScanResult } from '../types';
import { triggerHaptic, hapticPatterns } from '../lib/haptics';

const HistoryScreen: React.FC = () => {
  const { scans } = useUser();
  const [searchQuery, setSearchQuery] = useState('');
  const [showFilters, setShowFilters] = useState(false);
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const navigate = useNavigate();

  const filteredHistory = scans.filter(item => {
    const matchesSearch = item.foodName.toLowerCase().includes(searchQuery.toLowerCase());
    
    if (!startDate && !endDate) return matchesSearch;

    const itemDate = new Date(item.timestamp);
    const start = startDate ? startOfDay(new Date(startDate)) : new Date(0);
    const end = endDate ? endOfDay(new Date(endDate)) : new Date();

    const matchesDate = isWithinInterval(itemDate, { start, end });
    return matchesSearch && matchesDate;
  });

  const groupedHistory = filteredHistory.reduce((acc, item) => {
    const date = format(new Date(item.timestamp), 'MMMM d, yyyy');
    if (!acc[date]) acc[date] = [];
    acc[date].push(item);
    return acc;
  }, {} as Record<string, ScanResult[]>);

  return (
    <div className="space-y-10 pb-10">
      <div className="space-y-6">
        {/* Search Bar */}
        <div className="space-y-4">
          <div className="relative">
            <Search className="absolute left-5 top-1/2 -translate-y-1/2 text-gray-400" size={18} strokeWidth={2.5} />
            <input 
              type="text" 
              placeholder="Search your meals..." 
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full glass rounded-[24px] py-4 pl-14 pr-14 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-green-500/20 transition-all ios-shadow placeholder:text-gray-400"
            />
            <button 
              onClick={() => {
                triggerHaptic(hapticPatterns.light);
                setShowFilters(!showFilters);
              }}
              className={`absolute right-4 top-1/2 -translate-y-1/2 w-10 h-10 rounded-xl flex items-center justify-center transition-all ios-shadow ${showFilters ? 'bg-green-600 text-white' : 'glass text-gray-400'}`}
            >
              <Filter size={18} />
            </button>
          </div>

          <AnimatePresence>
            {showFilters && (
              <motion.div 
                initial={{ height: 0, opacity: 0 }}
                animate={{ height: 'auto', opacity: 1 }}
                exit={{ height: 0, opacity: 0 }}
                className="overflow-hidden"
              >
                <div className="glass-card p-8 rounded-[40px] space-y-6 border-white/50 ios-shadow mt-2">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <Calendar size={16} className="text-green-600" />
                      <h4 className="text-[10px] font-black uppercase tracking-[0.2em] text-gray-400">Date Range Filter</h4>
                    </div>
                    {(startDate || endDate) && (
                      <button 
                        onClick={() => {
                          triggerHaptic(hapticPatterns.light);
                          setStartDate('');
                          setEndDate('');
                        }}
                        className="text-[10px] font-black uppercase tracking-widest text-red-500 bg-red-50 px-3 py-1 rounded-full border border-red-100 flex items-center gap-1 active:scale-95 transition-all"
                      >
                        Clear <X size={12} />
                      </button>
                    )}
                  </div>
                  
                  <div className="grid grid-cols-2 gap-4">
                    <div className="space-y-3">
                      <label className="text-[10px] font-black text-gray-400 uppercase tracking-widest ml-1">Start Date</label>
                      <div className="relative group">
                        <Calendar size={14} className="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 group-focus-within:text-green-500 transition-colors" />
                        <input 
                          type="date" 
                          value={startDate}
                          onChange={(e) => {
                            triggerHaptic(hapticPatterns.light);
                            setStartDate(e.target.value);
                          }}
                          className="w-full glass rounded-2xl py-4 pl-10 pr-4 text-sm font-bold focus:outline-none focus:ring-4 focus:ring-green-500/10 transition-all appearance-none"
                        />
                      </div>
                    </div>
                    <div className="space-y-3">
                      <label className="text-[10px] font-black text-gray-400 uppercase tracking-widest ml-1">End Date</label>
                      <div className="relative group">
                        <Calendar size={14} className="absolute left-4 top-1/2 -translate-y-1/2 text-gray-400 group-focus-within:text-green-500 transition-colors" />
                        <input 
                          type="date" 
                          value={endDate}
                          onChange={(e) => {
                            triggerHaptic(hapticPatterns.light);
                            setEndDate(e.target.value);
                          }}
                          className="w-full glass rounded-2xl py-4 pl-10 pr-4 text-sm font-bold focus:outline-none focus:ring-4 focus:ring-green-500/10 transition-all appearance-none"
                        />
                      </div>
                    </div>
                  </div>

                  {/* Quick Filters */}
                  <div className="flex flex-wrap gap-2 pt-2">
                    {[
                      { label: 'Today', getValue: () => format(new Date(), 'yyyy-MM-dd') },
                      { label: 'Last 7 Days', getValue: () => format(new Date(Date.now() - 7 * 24 * 60 * 60 * 1000), 'yyyy-MM-dd') },
                      { label: 'This Month', getValue: () => format(new Date(new Date().getFullYear(), new Date().getMonth(), 1), 'yyyy-MM-dd') }
                    ].map((q) => (
                      <button
                        key={q.label}
                        onClick={() => {
                          triggerHaptic(hapticPatterns.light);
                          setStartDate(q.getValue());
                          setEndDate(format(new Date(), 'yyyy-MM-dd'));
                        }}
                        className="text-[10px] font-bold px-3 py-2 rounded-xl glass border-white/50 hover:bg-green-50 hover:text-green-600 transition-all active:scale-95"
                      >
                        {q.label}
                      </button>
                    ))}
                  </div>
                  
                  <p className="text-[10px] text-gray-400 font-medium leading-relaxed px-1">
                    Showing results from <span className="text-gray-900 font-bold">{startDate || 'the beginning'}</span> to <span className="text-gray-900 font-bold">{endDate || 'today'}</span>.
                  </p>
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>

      {/* History List */}
      <div className="space-y-10">
        {Object.keys(groupedHistory).length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20 text-center space-y-6">
            <div className="w-24 h-24 glass rounded-[40px] flex items-center justify-center text-gray-300 ios-shadow">
              <Apple size={48} strokeWidth={1.5} />
            </div>
            <div className="space-y-2">
              <h3 className="text-xl font-bold text-gray-900">No scans found</h3>
              <p className="text-sm text-gray-500 font-medium max-w-[200px] mx-auto">Start scanning your meals to build your history.</p>
            </div>
          </div>
        ) : (
          Object.entries(groupedHistory).map(([date, items]) => (
            <div key={date} className="space-y-5">
              <h3 className="text-[10px] font-bold uppercase tracking-[0.2em] text-gray-400 px-2">{date}</h3>
              <div className="space-y-4">
                <AnimatePresence mode="popLayout">
                  {items.map((item, idx) => (
                    <motion.div 
                      key={item.id}
                      initial={{ opacity: 0, y: 10 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={{ delay: idx * 0.05 }}
                      onClick={() => {
                        triggerHaptic(hapticPatterns.light);
                        navigate(`/result/${item.id}`);
                      }}
                      className="glass-card p-4 rounded-[32px] flex items-center gap-5 cursor-pointer hover:border-green-100 transition-all group ios-shadow"
                    >
                      <div className="w-16 h-16 rounded-2xl overflow-hidden bg-gray-100 flex-shrink-0 ios-shadow group-hover:scale-105 transition-transform">
                        <img 
                          src={item.imageUrl} 
                          alt={item.foodName} 
                          className="w-full h-full object-cover"
                          referrerPolicy="no-referrer"
                        />
                      </div>
                      <div className="flex-1 min-w-0 space-y-1">
                        <h4 className="font-bold text-gray-900 truncate text-lg tracking-tight">{item.foodName}</h4>
                        <div className="flex items-center gap-2">
                          {item.type === 'food' ? (
                            <span className="text-[10px] font-bold text-green-600 bg-green-50/50 px-2 py-0.5 rounded-full border border-green-100">
                              {item.calories} kcal
                            </span>
                          ) : (
                            <span className="text-[10px] font-bold text-blue-600 bg-blue-50/50 px-2 py-0.5 rounded-full border border-blue-100 uppercase tracking-widest">
                              {item.type}
                            </span>
                          )}
                          <span className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">
                            {format(new Date(item.timestamp), 'h:mm a')}
                          </span>
                        </div>
                      </div>
                      <div className="w-10 h-10 rounded-full bg-gray-50 flex items-center justify-center text-gray-300 group-hover:text-green-500 group-hover:bg-green-50 transition-all">
                        <ChevronRight size={20} />
                      </div>
                    </motion.div>
                  ))}
                </AnimatePresence>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
};

export default HistoryScreen;
