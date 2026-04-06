import { 
  collection, 
  doc, 
  setDoc, 
  getDoc, 
  getDocs, 
  query, 
  where, 
  orderBy, 
  limit, 
  onSnapshot, 
  addDoc, 
  Timestamp,
  deleteDoc,
  increment
} from 'firebase/firestore';
import { ref, uploadBytes, getDownloadURL } from 'firebase/storage';
import { db, auth, storage } from '../firebase';
import { UserProfile, ScanResult, ChatMessage, DailySummary } from '../types';

enum OperationType {
  CREATE = 'create',
  UPDATE = 'update',
  DELETE = 'delete',
  LIST = 'list',
  GET = 'get',
  WRITE = 'write',
}

function handleFirestoreError(error: unknown, operationType: OperationType, path: string | null) {
  const errInfo = {
    error: error instanceof Error ? error.message : String(error),
    authInfo: {
      userId: auth.currentUser?.uid,
      email: auth.currentUser?.email,
      emailVerified: auth.currentUser?.emailVerified,
      isAnonymous: auth.currentUser?.isAnonymous,
      tenantId: auth.currentUser?.tenantId,
      providerInfo: auth.currentUser?.providerData.map(provider => ({
        providerId: provider.providerId,
        displayName: provider.displayName,
        email: provider.email,
        photoUrl: provider.photoURL
      })) || []
    },
    operationType,
    path
  }
  console.error('Firestore Error: ', JSON.stringify(errInfo));
  throw new Error(JSON.stringify(errInfo));
}

export const uploadProfileImage = async (file: File): Promise<string> => {
  const user = auth.currentUser;
  if (!user) throw new Error("User not authenticated");
  
  const storageRef = ref(storage, `users/${user.uid}/profile_${Date.now()}`);
  await uploadBytes(storageRef, file);
  const downloadURL = await getDownloadURL(storageRef);
  
  // Update profile with new photoURL
  await saveUserProfile({ photoURL: downloadURL });
  
  return downloadURL;
};

export const uploadAIAvatar = async (file: File): Promise<string> => {
  const user = auth.currentUser;
  if (!user) throw new Error("User not authenticated");
  
  const storageRef = ref(storage, `users/${user.uid}/ai_avatar_${Date.now()}`);
  await uploadBytes(storageRef, file);
  const downloadURL = await getDownloadURL(storageRef);
  
  // Update profile with new aiAvatarURL
  await saveUserProfile({ aiAvatarURL: downloadURL });
  
  return downloadURL;
};

export const saveUserProfile = async (profile: Partial<UserProfile>) => {
  const user = auth.currentUser;
  if (!user) throw new Error("User not authenticated");
  
  const uid = user.uid;
  const path = `users/${uid}`;
  try {
    const userDoc = doc(db, 'users', uid);
    await setDoc(userDoc, {
      ...profile,
      uid,
      email: user.email,
      updatedAt: Timestamp.now()
    }, { merge: true });
  } catch (error) {
    handleFirestoreError(error, OperationType.WRITE, path);
  }
};

export const getUserProfile = async (uid: string): Promise<UserProfile | null> => {
  const path = `users/${uid}`;
  try {
    const userDoc = doc(db, 'users', uid);
    const snap = await getDoc(userDoc);
    if (snap.exists()) {
      return snap.data() as UserProfile;
    }
    return null;
  } catch (error) {
    handleFirestoreError(error, OperationType.GET, path);
    return null;
  }
};

export const updateDailySummary = async (scan: Omit<ScanResult, 'id' | 'userId' | 'timestamp'>) => {
  const uid = auth.currentUser?.uid;
  if (!uid) return;

  const date = new Date().toISOString().split('T')[0];
  const path = `users/${uid}/daily_summary/${date}`;
  
  try {
    const summaryDoc = doc(db, 'users', uid, 'daily_summary', date);
    await setDoc(summaryDoc, {
      date,
      totalCalories: increment(scan.calories),
      totalProtein: increment(scan.protein),
      totalCarbs: increment(scan.carbs),
      totalFats: increment(scan.fats),
    }, { merge: true });
  } catch (error) {
    handleFirestoreError(error, OperationType.WRITE, path);
  }
};

export const updateWaterIntake = async (amount: number) => {
  const uid = auth.currentUser?.uid;
  if (!uid) return;

  const date = new Date().toISOString().split('T')[0];
  const path = `users/${uid}/daily_summary/${date}`;
  
  try {
    const summaryDoc = doc(db, 'users', uid, 'daily_summary', date);
    await setDoc(summaryDoc, {
      date,
      totalWater: increment(amount),
    }, { merge: true });
  } catch (error) {
    handleFirestoreError(error, OperationType.WRITE, path);
  }
};

export const getDailySummary = (callback: (summary: DailySummary | null) => void) => {
  const uid = auth.currentUser?.uid;
  if (!uid) return () => {};

  const date = new Date().toISOString().split('T')[0];
  const path = `users/${uid}/daily_summary/${date}`;
  const summaryDoc = doc(db, 'users', uid, 'daily_summary', date);

  return onSnapshot(summaryDoc, (snap) => {
    if (snap.exists()) {
      callback(snap.data() as DailySummary);
    } else {
      callback(null);
    }
  }, (error) => {
    handleFirestoreError(error, OperationType.GET, path);
  });
};

export const saveScanResult = async (scan: Omit<ScanResult, 'id' | 'userId' | 'timestamp'>) => {
  const uid = auth.currentUser?.uid;
  if (!uid) throw new Error("User not authenticated");
  
  const path = 'scans';
  try {
    const scanData = {
      ...scan,
      userId: uid,
      timestamp: Timestamp.now(),
    };
    const docRef = await addDoc(collection(db, 'scans'), scanData);
    
    // Update daily summary
    await updateDailySummary(scan);
    
    return { ...scanData, id: docRef.id, timestamp: scanData.timestamp.toDate().toISOString() };
  } catch (error) {
    handleFirestoreError(error, OperationType.CREATE, path);
  }
};

export const getScanHistory = (callback: (scans: ScanResult[]) => void) => {
  const uid = auth.currentUser?.uid;
  if (!uid) return () => {};
  
  const path = 'scans';
  const q = query(
    collection(db, 'scans'),
    where('userId', '==', uid),
    orderBy('timestamp', 'desc'),
    limit(50)
  );
  
  return onSnapshot(q, (snapshot) => {
    const scans = snapshot.docs.map(doc => ({
      ...doc.data(),
      id: doc.id,
      timestamp: (doc.data().timestamp as Timestamp).toDate().toISOString()
    })) as ScanResult[];
    callback(scans);
  }, (error) => {
    handleFirestoreError(error, OperationType.LIST, path);
  });
};

export const saveChatMessage = async (role: 'user' | 'model', text: string) => {
  const uid = auth.currentUser?.uid;
  if (!uid) throw new Error("User not authenticated");
  
  const path = `users/${uid}/messages`;
  try {
    await addDoc(collection(db, 'users', uid, 'messages'), {
      userId: uid,
      role,
      text,
      timestamp: Timestamp.now()
    });
  } catch (error) {
    handleFirestoreError(error, OperationType.CREATE, path);
  }
};

export const getChatHistory = (callback: (messages: ChatMessage[]) => void) => {
  const uid = auth.currentUser?.uid;
  if (!uid) return () => {};
  
  const path = `users/${uid}/messages`;
  const q = query(
    collection(db, 'users', uid, 'messages'),
    orderBy('timestamp', 'asc'),
    limit(100)
  );
  
  return onSnapshot(q, (snapshot) => {
    const messages = snapshot.docs.map(doc => ({
      ...doc.data(),
      id: doc.id,
      timestamp: (doc.data().timestamp as Timestamp).toDate().toISOString()
    })) as ChatMessage[];
    callback(messages);
  }, (error) => {
    handleFirestoreError(error, OperationType.LIST, path);
  });
};

export const clearChatHistory = async () => {
  const uid = auth.currentUser?.uid;
  if (!uid) throw new Error("User not authenticated");
  
  const path = `users/${uid}/messages`;
  try {
    const q = query(collection(db, 'users', uid, 'messages'));
    const snapshot = await getDocs(q);
    const deletePromises = snapshot.docs.map(doc => deleteDoc(doc.ref));
    await Promise.all(deletePromises);
  } catch (error) {
    handleFirestoreError(error, OperationType.DELETE, path);
  }
};
