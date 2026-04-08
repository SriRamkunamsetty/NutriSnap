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
  const [selectedType, setSelectedType] = useState<string>('all');
  const [isFiltering, setIsFiltering] = useState(false);
  const navigate = useNavigate();

  const [filteredHistory, setFilteredHistory] = useState<ScanResult[]>(scans);

  React.useEffect(() => {
    setIsFiltering(true);
    const timer = setTimeout(() => {
      const filtered = scans.filter(item => {
        const matchesSearch = item.foodName.toLowerCase().includes(searchQuery.toLowerCase());
        const matchesType = selectedType === 'all' || item.type === selectedType;
        
        if (!startDate && !endDate) return matchesSearch && matchesType;

        const itemDate = new Date(item.timestamp);
        const start = startDate ? startOfDay(new Date(startDate)) : new Date(0);
        const end = endDate ? endOfDay(new Date(endDate)) : new Date();

        const matchesDate = isWithinInterval(itemDate, { start, end });
        return matchesSearch && matchesDate && matchesType;
      });
      setFilteredHistory(filtered);
      setIsFiltering(false);
    }, 300); // Small delay to show loader

    return () => clearTimeout(timer);
  }, [searchQuery, startDate, endDate, scans]);

  const groupedHistory = filteredHistory.reduce((acc, item) => {
    const date = format(new Date(item.timestamp), 'MMMM d, yyyy');
    if (!acc[date]) acc[date] = [];
    acc[date].push(item);
    return acc;
  }, {} as Record<string, ScanResult[]>);

  return (
    <div className="space-y-10 pb-10">
      <div className="space-y-6">
        {/* Search and Filters Bar */}
        <div className="flex gap-2 items-center">
          <div className="relative flex-1">
            <Search className="absolute left-5 top-1/2 -translate-y-1/2 text-gray-400" size={18} strokeWidth={2.5} />
            <input 
              type="text" 
              placeholder="Search meals..." 
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full glass rounded-[24px] py-4 pl-14 pr-4 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-green-500/20 transition-all ios-shadow placeholder:text-gray-400"
            />
          </div>
          
          <div className="flex gap-2 items-center">
            {/* Start Date Picker */}
            <div className="relative group">
              <input 
                type="date" 
                value={startDate}
                onChange={(e) => {
                  triggerHaptic(hapticPatterns.light);
                  setStartDate(e.target.value);
                }}
                className="absolute inset-0 w-full h-full opacity-0 cursor-pointer z-10"
              />
              <div className={`w-12 h-12 rounded-2xl flex items-center justify-center transition-all ios-shadow border border-white/50 ${startDate ? 'bg-green-600 text-white' : 'glass text-gray-400'}`}>
                <Calendar size={18} strokeWidth={2.5} />
                {startDate && <div className="absolute -top-1 -right-1 w-3 h-3 bg-red-500 rounded-full border-2 border-white" />}
              </div>
            </div>

            {/* End Date Picker */}
            <div className="relative group">
              <input 
                type="date" 
                value={endDate}
                onChange={(e) => {
                  triggerHaptic(hapticPatterns.light);
                  setEndDate(e.target.value);
                }}
                className="absolute inset-0 w-full h-full opacity-0 cursor-pointer z-10"
              />
              <div className={`w-12 h-12 rounded-2xl flex items-center justify-center transition-all ios-shadow border border-white/50 ${endDate ? 'bg-green-600 text-white' : 'glass text-gray-400'}`}>
                <Calendar size={18} strokeWidth={2.5} />
                {endDate && <div className="absolute -top-1 -right-1 w-3 h-3 bg-red-500 rounded-full border-2 border-white" />}
              </div>
            </div>

            {/* Filter Toggle */}
            <button 
              onClick={() => {
                triggerHaptic(hapticPatterns.light);
                setShowFilters(!showFilters);
              }}
              className={`w-12 h-12 rounded-2xl flex items-center justify-center transition-all ios-shadow border border-white/50 ${showFilters ? 'bg-green-600 text-white' : 'glass text-gray-400'}`}
            >
              <Filter size={18} strokeWidth={2.5} />
            </button>
          </div>
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
                    <Filter size={16} className="text-green-600" />
                    <h4 className="text-[10px] font-black uppercase tracking-[0.2em] text-gray-400">Advanced Filters</h4>
                  </div>
                  {(startDate || endDate || selectedType !== 'all') && (
                    <button 
                      onClick={() => {
                        triggerHaptic(hapticPatterns.light);
                        setStartDate('');
                        setEndDate('');
                        setSelectedType('all');
                      }}
                      className="text-[10px] font-black uppercase tracking-widest text-red-500 bg-red-50 px-3 py-1 rounded-full border border-red-100 flex items-center gap-1 active:scale-95 transition-all"
                    >
                      Clear All <X size={12} />
                    </button>
                  )}
                </div>
                
                {/* Type Filter */}
                <div className="space-y-3">
                  <label className="text-[10px] font-black text-gray-400 uppercase tracking-widest ml-1">Scan Type</label>
                  <div className="flex flex-wrap gap-2">
                    {['all', 'food', 'person', 'animal', 'other'].map((type) => (
                      <button
                        key={type}
                        onClick={() => {
                          triggerHaptic(hapticPatterns.light);
                          setSelectedType(type);
                        }}
                        className={`px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-widest transition-all ${
                          selectedType === type 
                            ? 'bg-green-600 text-white shadow-lg scale-105' 
                            : 'glass text-gray-400 hover:text-gray-600'
                        }`}
                      >
                        {type}
                      </button>
                    ))}
                  </div>
                </div>

                {/* Quick Date Filters */}
                <div className="space-y-3">
                  <label className="text-[10px] font-black text-gray-400 uppercase tracking-widest ml-1">Quick Date Range</label>
                  <div className="flex flex-wrap gap-2">
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
                </div>
                
                <p className="text-[10px] text-gray-400 font-medium leading-relaxed px-1">
                  Showing results from <span className="text-gray-900 font-bold">{startDate || 'the beginning'}</span> to <span className="text-gray-900 font-bold">{endDate || 'today'}</span>.
                </p>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* History List */}
      <div className="space-y-10 min-h-[400px] relative">
        <AnimatePresence mode="wait">
          {isFiltering ? (
            <motion.div 
              key="loader"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="flex flex-col items-center justify-center py-20 space-y-6"
            >
              <div className="relative w-20 h-20">
                <div className="absolute inset-0 border-4 border-green-500/10 rounded-full" />
                <div className="absolute inset-0 border-4 border-t-green-500 rounded-full animate-spin" />
                <div className="absolute inset-4 bg-green-50 rounded-full flex items-center justify-center">
                  <Apple size={24} className="text-green-500 animate-pulse" />
                </div>
              </div>
              <div className="text-center space-y-1">
                <p className="text-sm font-black text-gray-900 tracking-tight">Analyzing History</p>
                <p className="text-[10px] font-bold uppercase tracking-widest text-gray-400">Applying filters...</p>
              </div>
            </motion.div>
          ) : Object.keys(groupedHistory).length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20 text-center space-y-6">
            <div className="w-24 h-24 glass rounded-[40px] flex items-center justify-center text-gray-300 ios-shadow border border-white/50">
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
        </AnimatePresence>
      </div>
    </div>
  );
};

export default HistoryScreen;
