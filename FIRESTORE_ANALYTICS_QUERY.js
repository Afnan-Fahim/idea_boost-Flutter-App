// Query Analytics Events from Firestore
// Run this in Firebase Console → Firestore → Console tab

// Show all analytics events
db.collection('analytics_events')
  .orderBy('timestamp', 'desc')
  .limit(20)
  .get()
  .then(querySnapshot => {
    console.log(`📊 Found ${querySnapshot.size} analytics events:\n`);
    
    let eventCounts = {};
    
    querySnapshot.forEach(doc => {
      const data = doc.data();
      const event = data.event;
      
      // Count by event type
      eventCounts[event] = (eventCounts[event] || 0) + 1;
      
      // Print first 5 events
      if (Object.keys(eventCounts).length <= 5) {
        console.log(`✅ Event: ${event}`);
        console.log(`   User: ${data.userId}`);
        console.log(`   Tier: ${data.tier}`);
        console.log(`   Time: ${data.timestamp?.toDate()}`);
        console.log('');
      }
    });
    
    console.log('\n📈 Event Counts:');
    Object.entries(eventCounts).forEach(([event, count]) => {
      console.log(`  ${event}: ${count}`);
    });
  })
  .catch(err => console.error('Error:', err));
