 window.addEventListener('message', function(event) {
    let item = event.data;

    if (item.type === "ui") {
        const paper = document.getElementById('main-paper');
        
        if (item.status) {
            document.body.style.display = "flex";
            
            paper.classList.remove('fade-in');
            void paper.offsetWidth; 
            paper.classList.add('fade-in');
        } else {
            document.body.style.display = "none";
            paper.classList.remove('fade-in');
        }
    }

    if (item.type === "updateList") {
        if (item.list && item.progress) {
            setupTaskList(item.list, item.progress, item.playSound);
        }
    }
});

function setupTaskList(list, progress, playSound) {
    const container = document.getElementById('dynamic-task-container');
    const stamp = document.getElementById('approved-stamp');
    const streakCounter = document.getElementById('streak-counter');
    const streakNum = document.getElementById('streak-number');
    
    container.innerHTML = ''; 
    stamp.classList.remove('stamp-animation'); 

    if (progress.streak && progress.streak > 0) {
        streakCounter.style.display = 'block'; 
        streakNum.innerText = progress.streak;
    } else {
        streakCounter.style.display = 'none'; 
    }

    const ul = document.createElement('ul');
    ul.className = 'task-list';

    let allCompleted = true; 

    list.forEach(function(task, index) {
        const li = document.createElement('li');
        li.className = 'task-item';
        
        li.textContent = "Deliver a " + task.value.toUpperCase(); 

        let slotName = "slot" + (index + 1);
        
        if (progress[slotName] === 1) {
            setTimeout(() => {
                li.classList.add('crossed-out');
            }, 50 + (index * 150)); 
        } else {
            allCompleted = false; 
        }

        ul.appendChild(li);
    });

    container.appendChild(ul);

    if (allCompleted && list.length > 0) {
        setTimeout(() => {
            stamp.classList.add('stamp-animation');
            
            if (playSound) {
                let completionSound = new Audio('MissionPassed.mp3');
                completionSound.volume = 0.4; 
                completionSound.play();
            }
            
        }, 600); 
    }
}

document.getElementById('close').addEventListener('click', function() {
    fetch(`https://${GetParentResourceName()}/closeUI`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
});