import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Search, Filter, ChevronRight, Calendar, Apple } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { format } from 'date-fns';
import { useUser } from '../contexts/UserContext';
import { ScanResult } from '../types';

const HistoryScreen: React.FC = () => {
  const { scans } = useUser();
  const [searchQuery, setSearchQuery] = useState('');
  const navigate = useNavigate();

  const filteredHistory = scans.filter(item => 
    item.foodName.toLowerCase().includes(searchQuery.toLowerCase())
  );

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
        <div className="relative">
          <Search className="absolute left-5 top-1/2 -translate-y-1/2 text-gray-400" size={18} strokeWidth={2.5} />
          <input 
            type="text" 
            placeholder="Search your meals..." 
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full glass rounded-[24px] py-4 pl-14 pr-6 text-sm font-medium focus:outline-none focus:ring-2 focus:ring-green-500/20 transition-all ios-shadow placeholder:text-gray-400"
          />
          <div className="absolute right-4 top-1/2 -translate-y-1/2 w-8 h-8 glass rounded-xl flex items-center justify-center text-gray-400 ios-shadow">
            <Filter size={16} />
          </div>
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
                      onClick={() => navigate(`/result/${item.id}`)}
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
